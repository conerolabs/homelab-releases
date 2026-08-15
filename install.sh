#!/bin/bash
RELEASE_URL='https://github.com/conerolabs/homelab-releases/raw/test/conerhomelab-2_0_0-alpha.tar.gz' #TODO
TMP_DIR=~/tmp/homelabinstaller
HOMELAB_DIR=$TMP_DIR/homelab
INSTALL_DATA_DIR=$TMP_DIR/install

read -r -p "Enter the Homelab installation directory (default: ~/conerhomelab): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-~/conerhomelab}
# Backup existing installation if present
cp -r "$INSTALL_DIR" "$INSTALL_DIR".backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

#0. Downloads and extracts the release files from the repository in a tmp directory
echo "Downloading and extracting release files from repository ..."
mkdir -p "$TMP_DIR"
curl -sSL "$RELEASE_URL" | tar -xz -C "$TMP_DIR"

#1. Copy old values of previously installed homelab's .env file into the tmp installer directory ($HOMELAB_DIR)
# A subsequent step in the setup scripts will sync the .env file from the $TMP_DIR/install directory
if [ -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env" "$HOMELAB_DIR/.env"
else
    echo "INSTALL_DIR=$INSTALL_DIR" > "$HOMELAB_DIR/.env"
fi  

# load env variables from the template
# Update homelab/.env file
# - rimuove variabili non più utilizzate
# - aggiunge le nuove
# - aggiorna tutti i valori che nel template non sono vuoti
# - chiede all'utente di inserire i valori mancanti # Possiamo farlo in web-config invece che con uno script.
python3 -c "from setup_env import setup_env; setup_env('$INSTALL_DATA_DIR/.env', '$HOMELAB_DIR/.env')"
#! You need to run the script from inside INSTALL_DIR/install/scripts, otherwise the relative paths will not work

#2. Copy old secrets files in the installer directory
echo "Mantaining existing secrets files if present ..."
cp -r "$INSTALL_DIR"/authelia/secrets "$HOMELAB_DIR"/authelia/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/vaultwarden/secrets "$HOMELAB_DIR"/vaultwarden/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/gatus/secrets "$HOMELAB_DIR"/gatus/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/rustical/secrets "$HOMELAB_DIR"/rustical/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/web-config/secrets "$HOMELAB_DIR"/web-config/secrets 2>/dev/null || true

docker compose -f "$INSTALL_DIR"/docker-compose.yml down || true

# TODO: Valuate if to run pre-install script (for example to update the OS) or directly the setup scripts
# TODO: Valuate if to run deps-install script (for example to install docker) or directly the setup scripts
# At the moment we will run deps-install script from web config ui
#bash $TMP_DIR/install/scripts/1-deps-install.sh

#3. Run setup scripts
# At the moment we will run setup script from web config ui
#bash $TMP_DIR/install/scripts/2-setup.sh

#4. Copy homelab files into installation directory
echo "Copying homelab files into $INSTALL_DIR ..."
# Remove INSTALL_DIR for a fresh installation
rm -rf "$INSTALL_DIR" || echo "Installation directory not found, creating a new one"
mkdir -p "$INSTALL_DIR"
# L'opzione -u di cp copia solo i file che sono più recenti di quelli già presenti nella destinazione, evitando di sovrascrivere file più recenti con versioni più vecchie.
# L'opzione -u mantiene inoltre i file nella destinazione se non esistono nella sorgente, evitando di cancellare file che potrebbero essere stati creati o modificati dopo l'installazione iniziale.
# L'opzione -r è necessaria per copiare ricorsivamente le directory e i loro contenuti.
sudo cp -ru $HOMELAB_DIR/. "$INSTALL_DIR"/

# Occorrerà dunque eliminare manualmente i file che non servono più, ad esempio quelli generati dai container dopo l'installazione iniziale.
# In questo modo, se in futuro aggiorneremo i file di configurazione nella cartella homelab, basterà rilanciare questo script per copiare solo i file aggiornati, senza sovrascrivere quelli che sono stati modificati manualmente dopo l'installazione iniziale.
# sudo rm -f $TO_REMOVE_FILES
# sudo rm -rf $TO_REMOVE_DIRS

echo "Cleaning up temporary installation files ..."
rm -rf "$TMP_DIR"

#docker compose -f "$INSTALL_DIR"/docker-compose.yml up -d
