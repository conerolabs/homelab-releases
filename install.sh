#!/bin/bash
set -eo pipefail

RELEASE_URL='https://github.com/conerolabs/homelab-releases/raw/test/conerhomelab-2_0_0-alpha.tar.gz' #TODO
TMP_DIR="$HOME/tmp/homelabinstaller"
HOMELAB_DIR="$TMP_DIR/homelab"
INSTALL_DATA_DIR="$TMP_DIR/install"
BACKUP_DIR=""
WEB_CONFIG_APP="web-config-app"

NVM_VERSION='v0.40.6'
NODE_VERSION='v24.18.0'

installNodejs() {
    ## Install nvm and nodejs
    # check for nvm installed: if not installed, install it.
    if command -v nvm &> /dev/null; then
        echo "nvm is already installed"
    else
        echo "nvm is not installed, installing it..."
        # sudo apt update
        # sudo apt install curl -y
        cd "$HOME"
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
        export NVM_DIR="$HOME/.nvm"
        #source "$HOME/.bashrc"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
    fi

    NODE_CUR_VER=$(node -v 2>/dev/null || true)
    if [ -n "$NODE_VERSION" ] && [ "$NODE_CUR_VER" == "$NODE_VERSION" ]; then
        echo "Node $NODE_VERSION is already installed"
    else
        echo "Node $NODE_VERSION is not installed, installing it..."
        # Install nodejs (LTS version)
        # nvm install --lts
        if [ -n "$NODE_VERSION" ]; then
            nvm install "$NODE_VERSION"
        fi
    fi

    if command -v pm2 &> /dev/null; then
        echo "pm2 is already installed"
        # if process is running, delete it (we'll restart it after reinstallation)
        pm2 delete $WEB_CONFIG_APP 2>/dev/null || true
    else
        echo "pm2 is not installed, installing it..."
        npm install pm2 -g
        pm2 completion install
        eval "$(pm2 startup | tail -n 1)" # create systemd entries to run pm2 on hostreboot
    fi
}

# Function to clean up temporary directory and restore backup on error
cleanup() {
    local exit_code=$?
    trap - EXIT
    set +e
    if [ $exit_code -ne 0 ]; then
        echo -e "\nAn error occurred during installation (exit code: $exit_code)."

        if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
            echo "Restoring installation directory from backup $BACKUP_DIR ..."
            rm -rf "$INSTALL_DIR" 2>/dev/null || sudo rm -rf "$INSTALL_DIR"
            mv "$BACKUP_DIR" "$INSTALL_DIR" 2>/dev/null || sudo mv "$BACKUP_DIR" "$INSTALL_DIR"
            echo "Backup restored successfully."
        fi

        # Disable pm2 on reboot
        if [ -f /etc/systemd/system/pm2-"$USER".service ]; then
            eval "$(pm2 unstartup systemd | tail -n 1)"
        fi
    fi
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        echo "Cleaning up temporary directory $TMP_DIR ..."
        if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
            echo "You can eventually restore previous installation from $BACKUP_DIR directory"
        fi
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

installNodejs

echo
echo "To mantain existing settings, enter the same installation directory. Otherwise, a new one for a fresh install."
read -r -p "Installation directory (default: $HOME/conerhomelab): " INSTALL_DIR < /dev/tty
INSTALL_DIR=${INSTALL_DIR:-"$HOME/conerhomelab"}

# Backup existing installation if present
if [ -d "$INSTALL_DIR" ]; then
    CURRENT_BACKUP="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing installation to $CURRENT_BACKUP ..."
    cp -r "$INSTALL_DIR" "$CURRENT_BACKUP"
    BACKUP_DIR="$CURRENT_BACKUP"
fi

#0. Downloads and extracts the release files from the repository in a tmp directory
echo "Downloading and extracting release files from repository ..."
mkdir -p "$TMP_DIR"
curl -sSL "$RELEASE_URL" | tar -xz -C "$TMP_DIR"

#1. Copy old values of previously installed homelab's .env file into the tmp installer directory ($HOMELAB_DIR)
# A subsequent step in the script will sync the .env file from the $TMP_DIR/install directory
if [ -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env" "$HOMELAB_DIR/.env"
    node "$INSTALL_DATA_DIR/scripts/setup_enabled.ts" "$INSTALL_DIR/homelab.db" "$HOMELAB_DIR/homelab.db"
else
    echo "INSTALL_DIR=$INSTALL_DIR" > "$HOMELAB_DIR/.env"
fi

# load env variables from the template
# Update homelab/.env file
# - rimuove variabili non più utilizzate
# - aggiunge le nuove
# - aggiorna tutti i valori che nel template non sono vuoti
# - chiede all'utente di inserire i valori mancanti # Possiamo farlo in web-config invece che con uno script.
node "$INSTALL_DATA_DIR/scripts/setup_env.ts" "$INSTALL_DATA_DIR/.env" "$HOMELAB_DIR/.env" "INSTALL_DIR=$INSTALL_DIR"
#! You need to run the script from inside INSTALL_DIR/install/scripts, otherwise the relative paths will not work

#2. Copy old secrets files in the installer directory
echo "Mantaining existing secrets files if present ..."
cp -r "$INSTALL_DIR"/authelia/secrets "$HOMELAB_DIR"/authelia/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/vaultwarden/secrets "$HOMELAB_DIR"/vaultwarden/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/gatus/secrets "$HOMELAB_DIR"/gatus/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/rustical/secrets "$HOMELAB_DIR"/rustical/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/web-config/secrets "$HOMELAB_DIR"/web-config/secrets 2>/dev/null || true

docker compose -f "$INSTALL_DIR"/docker-compose.yml down 2>/dev/null || true

# TODO: Valuate if to run pre-install script (for example to update the OS) or directly the setup scripts
# TODO: Valuate if to run deps-install script (for example to install docker) or directly the setup scripts
# At the moment we will run deps-install script from web config ui
#bash $TMP_DIR/install/scripts/1-deps-install.sh

#3. Run setup scripts
# At the moment we will run setup script from web config ui
#bash $TMP_DIR/install/scripts/2-setup.sh

#4. Copy homelab files into installation directory
echo -n "Copying homelab files into $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
# L'opzione -u di cp copia solo i file che sono più recenti di quelli già presenti nella destinazione, evitando di sovrascrivere file più recenti con versioni più vecchie.
# L'opzione -u mantiene inoltre i file nella destinazione se non esistono nella sorgente, evitando di cancellare file che potrebbero essere stati creati o modificati dopo l'installazione iniziale.
# L'opzione -r è necessaria per copiare ricorsivamente le directory e i loro contenuti.
cp -ru "$HOMELAB_DIR"/. "$INSTALL_DIR"/
echo "  - COPIED"

# Occorrerà dunque eliminare manualmente i file che non servono più, ad esempio quelli generati dai container dopo l'installazione iniziale.
# In questo modo, se in futuro aggiorneremo i file di configurazione nella cartella homelab, basterà rilanciare questo script per copiare solo i file aggiornati, senza sovrascrivere quelli che sono stati modificati manualmente dopo l'installazione iniziale.
# sudo rm -f $TO_REMOVE_FILES
# sudo rm -rf $TO_REMOVE_DIRS

cd "$INSTALL_DIR"/web-config/commons
npm install

# TODO: deploy web config app (server + ui)
cd "$INSTALL_DIR"/web-config/backend
npm install
pm2 start ecosystem.config.js --env production
pm2 save
pm2 logs $WEB_CONFIG_APP --lines 24 --nostream

#docker compose -f "$INSTALL_DIR"/docker-compose.yml up -d
