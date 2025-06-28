#!/bin/bash

################################################################################
# Script de conversion vidéo matériel (Intel QuickSync H.265)
#
# - Conversion automatique des vidéos du dossier d'entrée vers le dossier de sortie en H.265 (HEVC).
# - Si le fichier source est MKV, conversion en MKV H.265 en conservant toutes
#   les pistes audio, sous-titres et chapitres.
# - Sinon, conversion en MP4 H.265 en conservant les pistes audio.
# - Conserve la profondeur de couleur (bit depth) d’origine (8, 10 ou 12 bits)
#   si le matériel le permet.
# - Option de suppression du fichier source et de son répertoire parent (si vide)
#   UNIQUEMENT si la conversion a réussi.
# - Respecte l'arborescence d'origine dans le dossier de sortie.
# - Affiche la progression de la conversion toutes les 10% dans la console.
# - Journalise les erreurs dans /tmp/erreurs_conversion.log (global)
#   et dans un fichier error.log détaillé dans le dossier de sortie.
# - Ignore les fichiers .log lors du traitement.
# - Gère un pool de conversions en parallèle : dès qu'un job se termine,
#   un nouveau peut être lancé sans attendre les autres.
#
# Usage : Prévu pour être utilisé dans un conteneur Docker.
#         La configuration se fait via les variables d'environnement.
#
# Variables d'environnement configurables :
#   - DELETE_SOURCE     : Si "true", supprime le fichier et répertoire source après
#                         conversion réussie. (défaut: "true")
#   - MAX_JOBS          : Nombre de conversions en parallèle. (défaut: 2)
#   - INPUT_DIR         : Répertoire source des vidéos à convertir. (défaut: /input)
#   - OUTPUT_DIR        : Répertoire de destination des vidéos converties. (défaut: /output)
#   - LOOP_WAIT_SECONDS : Temps d'attente en secondes entre chaque balayage du
#                         dossier d'entrée. (défaut: 30)
#
# Auteur : (à compléter)
# Date   : Juin 2025
# Version: 3.0 (Configuration via variables d'environnement)

# --- Variables Configurables via l'Environnement ---
DELETE_SOURCE="${DELETE_SOURCE:-true}"
MAX_JOBS="${MAX_JOBS:-2}"
INPUT_DIR="${INPUT_DIR:-/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
LOOP_WAIT_SECONDS="${LOOP_WAIT_SECONDS:-30}"

# --- Variables Globales Internes ---
INSTALL_FLAG="/tmp/.install_done"
GLOBAL_ERROR_LOG="/tmp/erreurs_conversion.log"


################################################################################
# FONCTIONS UTILITAIRES
################################################################################

# ------------------------------------------------------------------------------
# install_dependencies
# But : Installe les dépendances nécessaires pour l'encodage Intel QSV.
#       Cette fonction est exécutée une seule fois au démarrage si le drapeau
#       d'installation n'est pas trouvé.
# Entrées : Aucune
# Sorties : Affiche des messages d'installation ou d'erreur.
# Retourne : 0 si succès, 1 si échec de l'installation.
# ------------------------------------------------------------------------------
install_dependencies() {
    if [ ! -f "$INSTALL_FLAG" ]; then
        echo "INFO: Installation des dépendances..."
        # L'installation de 'procps' est une bonne pratique pour s'assurer que
        # les outils de gestion de processus sont disponibles.
        apt update && apt install -y vainfo intel-media-va-driver-non-free libmfx1 libva-drm2 libva2 procps
        if [ $? -eq 0 ]; then
            touch "$INSTALL_FLAG"
            echo "INFO: Dépendances installées avec succès."
        else
            echo "ERREUR: Échec de l'installation des dépendances." | tee -a "$GLOBAL_ERROR_LOG"
            exit 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# get_global_quality
# But : Détermine un paramètre 'global_quality' pour ffmpeg basé sur le bitrate
#       vidéo source, afin d'optimiser la qualité/taille du fichier de sortie.
# Entrées :
#   $1 : Bitrate vidéo en bits par seconde (bps).
# Sorties : Aucune (echo la valeur calculée)
# Retourne : La valeur de global_quality (nombre entier).
# ------------------------------------------------------------------------------
get_global_quality() {
    local bitrate=$1
    # Valeur par défaut si le bitrate n'est pas un nombre
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        bitrate=1000000
    fi
    if (( bitrate < 800000 )); then
        echo 24 # Qualité plus basse pour les faibles bitrates
    elif (( bitrate < 2000000 )); then
        echo 22
    elif (( bitrate < 5000000 )); then
        echo 20
    else
        echo 18 # Meilleure qualité pour les bitrates élevés
    fi
}

# ------------------------------------------------------------------------------
# get_bitrate
# But : Récupère le bitrate vidéo de la première piste vidéo d'un fichier.
# Entrées :
#   $1 : Chemin complet du fichier vidéo.
# Sorties : Aucune (echo le bitrate en bps)
# Retourne : Le bitrate en bps, ou une valeur par défaut (1Mbps) si non trouvé.
# ------------------------------------------------------------------------------
get_bitrate() {
    local file="$1"
    local bitrate
    bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 "$file")
    if ! [[ "$bitrate" =~ ^[0-9]+$ ]]; then
        echo "1000000" # Bitrate par défaut (1 Mbps)
    else
        echo "$bitrate"
    fi
}

# ------------------------------------------------------------------------------
# get_duration
# But : Récupère la durée totale d'une vidéo en secondes.
# Entrées :
#   $1 : Chemin complet du fichier vidéo.
# Sorties : Aucune (echo la durée en secondes)
# Retourne : La durée en secondes, ou une valeur par défaut (1 seconde) si non trouvée.
# ------------------------------------------------------------------------------
get_duration() {
    local file="$1"
    local duration
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file")
    duration=${duration%.*} # Supprime la partie décimale
    if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
        echo "1" # Durée par défaut (1 seconde) pour éviter la division par zéro
    else
        echo "$duration"
    fi
}

# ------------------------------------------------------------------------------
# get_pix_fmt_option
# But : Détecte la profondeur de couleur (bit depth) de la vidéo source
#       et retourne l'option ffmpeg `-pix_fmt` correspondante pour QSV.
# Entrées :
#   $1 : Chemin complet du fichier vidéo.
# Sorties : Aucune (echo l'option ffmpeg ou chaîne vide)
# Retourne : Chaîne "-pix_fmt p010le" pour 10 bits, "-pix_fmt p012le" pour 12 bits,
#            ou chaîne vide pour 8 bits (valeur par défaut de QSV).
# ------------------------------------------------------------------------------
get_pix_fmt_option() {
    local file="$1"
    local pix_fmt
    pix_fmt=$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt \
        -of default=noprint_wrappers=1:nokey=1 "$file")
    case "$pix_fmt" in
        yuv420p10le|p010le)
            echo "-pix_fmt p010le"
            ;;
        yuv420p12le|p012le)
            echo "-pix_fmt p012le"
            ;;
        *)
            echo "" # Pour les formats 8 bits, pas besoin de spécifier -pix_fmt
            ;;
    esac
}

################################################################################
# FONCTION PRINCIPALE DE CONVERSION
################################################################################

# ------------------------------------------------------------------------------
# convert_file
# But : Convertit une vidéo en H.265 (HEVC) matériel via Intel QSV,
#       en conservant la profondeur de couleur (8/10/12 bits) si supporté.
# Entrées :
#   $1 : Chemin complet du fichier source.
#   $2 : Chemin relatif du fichier source (pour les messages de log).
#   $3 : Chemin complet du fichier de sortie.
#   $4 : Options de mappage spécifiques à ffmpeg (ex : "-map 0:v:0 -map 0:a -map 0:s").
#   $5 : Option de copie de sous-titres (ex : "-c:s copy" ou chaîne vide).
#   $6 : Chemin du fichier de log temporaire pour les erreurs ffmpeg (généré par mktemp).
# Sorties : Affiche la progression et les messages de succès/échec.
# Retourne : 0 si la conversion réussit, un code d'erreur non nul sinon.
# ------------------------------------------------------------------------------
convert_file() {
    local file="$1"
    local relpath="$2"
    local outputfile="$3"
    local ffmpeg_extra_maps="$4"
    local subtitle_copy_option="$5"
    local ffmpeg_log_tmp="$6" # Reçoit le chemin du fichier temporaire généré par mktemp

    echo "INFO: Début de conversion : $relpath"

    # Crée le répertoire de sortie si nécessaire
    mkdir -p "$(dirname "$outputfile")" || {
        echo "ERREUR: Impossible de créer le répertoire de sortie pour $relpath." | tee -a "$GLOBAL_ERROR_LOG"
        return 1
    }

    # Récupération des paramètres d'encodage
    local bitrate=$(get_bitrate "$file")
    local global_quality=$(get_global_quality "$bitrate")
    local duration=$(get_duration "$file") # Durée en secondes pour la progression
    local pix_fmt_option
    pix_fmt_option=$(get_pix_fmt_option "$file")

    local ffmpeg_filters=""
    local ffmpeg_device_init=""
    local ffmpeg_pix_fmt=""

    # Configuration spécifique pour le 10/12 bits avec QSV
    if [[ "$pix_fmt_option" == "-pix_fmt p010le" ]]; then
        ffmpeg_filters="-vf vpp_qsv=format=p010le"
        ffmpeg_device_init="-init_hw_device qsv=hw:/dev/dri/renderD128 -filter_hw_device hw"
        ffmpeg_pix_fmt="-pix_fmt p010le"
    elif [[ "$pix_fmt_option" == "-pix_fmt p012le" ]]; then
        ffmpeg_filters="-vf vpp_qsv=format=p012le"
        ffmpeg_device_init="-init_hw_device qsv=hw:/dev/dri/renderD128 -filter_hw_device hw"
        ffmpeg_pix_fmt="-pix_fmt p012le"
    fi

    local start_time=$(date +%s)
    local progress_fifo
    progress_fifo=$(mktemp -u) # Utilise mktemp pour un nom de FIFO unique
    mkfifo "$progress_fifo" || {
        echo "ERREUR: Impossible de créer le FIFO $progress_fifo pour $relpath." | tee -a "$GLOBAL_ERROR_LOG"
        return 1
    }

    # Affichage de la progression par paliers de 10%
    (
        local last_percent=0
        while IFS= read -r line; do
            if [[ "$line" =~ out_time_ms=([0-9]+) ]]; then
                local out_time_ms=${BASH_REMATCH[1]}
                local current_seconds=$((out_time_ms / 1000000))
                local percent=0
                if (( duration > 0 )); then
                    percent=$(( (current_seconds * 100) / duration ))
                fi
                local next_ten_percent=$(((last_percent / 10 + 1) * 10))
                if (( percent >= next_ten_percent && next_ten_percent <= 100 )); then
                    echo "PROGRESSION ($relpath): $next_ten_percent%"
                    last_percent=$next_ten_percent
                fi
            fi
        done < "$progress_fifo"
    ) &
    local progress_pid=$!

    # Lancement de la commande ffmpeg
    # -nostdin : Empêche ffmpeg de lire l'entrée standard, utile dans les scripts.
    # -y : Écrase le fichier de sortie sans demander confirmation.
    # -hide_banner : Supprime le bandeau d'information de ffmpeg.
    # -loglevel error -nostats : Réduit la sortie de ffmpeg aux erreurs, désactive les stats standard.
    # -progress : Indique à ffmpeg d'écrire la progression dans le FIFO spécifié.
    stdbuf -oL ffmpeg -nostdin -y -hide_banner \
        $ffmpeg_device_init \
        -i "$file" \
        $ffmpeg_filters \
        -c:v hevc_qsv $ffmpeg_pix_fmt -global_quality "$global_quality" -preset slow -look_ahead 1 \
        -c:a copy \
        $subtitle_copy_option \
        $ffmpeg_extra_maps \
        -movflags +faststart \
        -loglevel error -nostats \
        -progress "$progress_fifo" \
        "$outputfile" 2> "$ffmpeg_log_tmp"
    local retcode=$?

    # Attendre que le processus de lecture de la progression se termine
    wait $progress_pid
    # Supprimer le FIFO temporaire
    rm -f "$progress_fifo"

    # Enregistrement du temps écoulé pour la conversion
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local elapsed_hms=$(printf '%02d:%02d:%02d' $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))

    if [[ $retcode -eq 0 ]]; then
        echo "INFO: Conversion réussie : $relpath (durée : $elapsed_hms)"
        # Note : Le fichier ffmpeg_log_tmp est supprimé par le shell parent après traitement
    else
        echo "ERREUR: Échec de la conversion de $relpath" | tee -a "$GLOBAL_ERROR_LOG"
    fi
    return $retcode
}

################################################################################
# GESTION DU POOL DE TRAITEMENT PARALLÈLE
################################################################################

# ------------------------------------------------------------------------------
# wait_for_slot
# But : Attend qu'une place se libère dans le pool de jobs en utilisant
#       la gestion de jobs native du shell. Permet de lancer un nouveau job
#       dès qu'un slot se libère, sans attendre tous les autres.
# ------------------------------------------------------------------------------
wait_for_slot() {
    # 'jobs -p' liste les PIDs des processus en arrière-plan.
    # 'wc -l' compte le nombre de lignes, donc le nombre de jobs.
    while (($(jobs -p | wc -l) >= MAX_JOBS)); do
        # 'wait -n' attend qu'un job en arrière-plan se termine sans spécifier de PID.
        # Cela permet de libérer un slot dès qu'il y en a un.
        wait -n
        sleep 0.5 # Petite pause pour éviter de sonder trop agressivement
    done
}

################################################################################
# BOUCLE PRINCIPALE DU SCRIPT
# TRAITEMENT DES FICHIERS EN PARALLÈLE
################################################################################

# ------------------------------------------------------------------------------
# main_loop
# But : Boucle principale qui surveille le répertoire d'entrée et traite
#       les fichiers en continu.
# ------------------------------------------------------------------------------
main_loop() {
    echo "--- Démarrage du script de conversion vidéo ---"
    echo "Configuration :"
    echo " - Dossier d'entrée   : $INPUT_DIR"
    echo " - Dossier de sortie  : $OUTPUT_DIR"
    echo " - Jobs parallèles    : $MAX_JOBS"
    echo " - Suppression source : $DELETE_SOURCE"
    echo " - Délai de boucle    : $LOOP_WAIT_SECONDS secondes"
    echo "-----------------------------------------------"
    
    # Activation du mode "monitor" (job control), essentiel pour `jobs`.
    set -m

    install_dependencies
    
    echo "--- Démarrage de la surveillance du répertoire $INPUT_DIR ---"
    while true; do
        # Utilise 'find' comme un flux producteur. La boucle 'while read'
        # consomme chaque fichier un par un.
        # L'utilisation de 'find ... -print0 | while ... read -d ""' est
        # la méthode la plus robuste pour gérer tous les types de noms de fichiers.
        find "$INPUT_DIR" -type f -print0 | while IFS= read -r -d '' infile_full_path; do
            # Récupère le chemin relatif pour les logs et le nom de sortie
            local relpath="${infile_full_path#$INPUT_DIR/}"
            local extension="${relpath##*.}"

            # Ignorer les fichiers .log
            if [[ "${extension,,}" == "log" ]]; then
                continue
            fi

            local outname outputfile ffmpeg_extra_maps subtitle_copy_option

            if [[ "${extension,,}" == "mkv" ]]; then
                outname="${relpath%.*}.mkv"
                outputfile="$OUTPUT_DIR/$outname"
                # Pour les MKV, conserver toutes les pistes et les chapitres,
                # exclure les données d'attachement qui peuvent parfois poser problème ou ne pas être nécessaires.
                ffmpeg_extra_maps="-map 0 -map -0:d" 
                subtitle_copy_option="-c:s copy"
            else
                outname="${relpath%.*}.mp4"
                outputfile="$OUTPUT_DIR/$outname"
                # Pour les autres formats convertis en MP4, copier vidéo et audio par défaut.
                # Les sous-titres sont souvent traités différemment en MP4 (text track, pas stream)
                # et peuvent être encodés en dur si nécessaire via un filtre -vf subtitles=...
                ffmpeg_extra_maps="" 
                subtitle_copy_option="" # Ne pas copier les sous-titres directement pour les MP4 par défaut
            fi

            # Si le fichier de sortie existe déjà, on saute le traitement.
            if [[ -f "$outputfile" ]]; then
                continue
            fi

            # Attendre une place libre dans le pool avant de lancer la conversion
            wait_for_slot

            # Lancer la conversion en arrière-plan dans un sous-shell
            (
                local outdir
                outdir="$(dirname "$outputfile")"
                
                # Utiliser mktemp pour générer un nom de fichier temporaire sûr et court
                local log_tmp=$(mktemp /tmp/ffmpeg_log_XXXXXX.log)
                if [[ ! -f "$log_tmp" ]]; then
                    echo "ERREUR: Impossible de créer un fichier temporaire pour le log FFMPEG." | tee -a "$GLOBAL_ERROR_LOG"
                    exit 1 # Quitter ce sous-shell si mktemp échoue
                fi
                
                convert_file "$infile_full_path" "$relpath" "$outputfile" "$ffmpeg_extra_maps" "$subtitle_copy_option" "$log_tmp"
                local status=$?

                if [[ $status -ne 0 ]]; then
                    local ffmpeg_log_detail="$outdir/error.log"
                    {
                        echo "----------------------------------------------------"
                        echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
                        echo "Fichier : $relpath"
                        echo "Chemin source: $infile_full_path"
                        echo "Chemin sortie: $outputfile"
                        echo "Code erreur : $status"
                        echo "Message : Échec de la conversion."
                        echo "---- DÉTAILS DE L'ERREUR FFMPEG ----"
                        cat "$log_tmp"
                        echo "----------------------------------------------------"
                    } >> "$ffmpeg_log_detail"                
                else
                    # La conversion a réussi (status = 0)
                    # On vérifie si la suppression est activée
                    if [[ "${DELETE_SOURCE,,}" == "true" ]]; then
                        echo "INFO: Suppression du fichier source réussi : $relpath"
                        rm -f "$infile_full_path"

                        # Supprimer récursivement les répertoires vides jusqu'à INPUT_DIR
                        local current_dir
                        current_dir=$(dirname "$infile_full_path")
                        # S'assurer qu'on ne supprime pas le dossier d'entrée lui-même
                        while [[ "$current_dir" != "$INPUT_DIR" && "$current_dir" != "/" ]]; do
                            # Vérifier si le répertoire est vide (ne contient que des entrées '.' et '..')
                            if [ -z "$(ls -A "$current_dir")" ]; then
                                echo "INFO: Suppression du répertoire source vide : $current_dir"
                                rmdir "$current_dir" || break # Arrête si rmdir échoue (ex: non vide, permissions)
                                current_dir=$(dirname "$current_dir") # Remonte au répertoire parent
                            else
                                break # Le répertoire n'est pas vide, on arrête de remonter
                            fi
                        done
                    else
                         echo "INFO: Conversion réussie. La suppression du fichier source est désactivée (DELETE_SOURCE!=true)."
                    fi
                fi
                # Assurez-vous que le fichier temporaire est toujours supprimé, même en cas d'erreur
                rm -f "$log_tmp"
            ) &
        done

        # Attendre la fin de tous les jobs lancés lors de cette passe de 'find'
        # avant de faire une pause et de scanner de nouveau.
        wait

        echo "--- Passe de vérification terminée. Attente de $LOOP_WAIT_SECONDS secondes avant la prochaine. ---"
        sleep "$LOOP_WAIT_SECONDS"
    done
}

################################################################################
# POINT D'ENTRÉE
################################################################################

main_loop