#!/bin/bash
RELEASE_URL='' #TODO
TMP_DIR=~/tmp/homelabinstaller
HOMELAB_DIR=$TMP_DIR/homelab

read -r -p "Enter the Homelab installation directory (default: ~/conerhomelab): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-~/conerhomelab}
# Backup existing installation if present
cp -r "$INSTALL_DIR" "$INSTALL_DIR".backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

#0. Download the release files from the repository
echo "Downloading release files from repository ..."
mkdir -p "$TMP_DIR"
curl -sSL "$RELEASE_URL" | tar -xz -C "$TMP_DIR"

# Copy old values of .env file in the installer directory ($HOMELAB_DIR)
if [ -f "$INSTALL_DIR/.env" ]; then
    cp "$INSTALL_DIR/.env" "$HOMELAB_DIR/.env"
else
    echo "INSTALL_DIR=$INSTALL_DIR" > "$HOMELAB_DIR/.env"
fi   

# Copy old secrets files in the installer directory
echo "Mantaining existing secrets files if present ..."
cp -r "$INSTALL_DIR"/authelia/secrets "$HOMELAB_DIR"/authelia/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/vaultwarden/secrets "$HOMELAB_DIR"/vaultwarden/secrets 2>/dev/null || true
cp -r "$INSTALL_DIR"/gatus/secrets "$HOMELAB_DIR"/gatus/secrets 2>/dev/null || true

docker compose -f "$INSTALL_DIR"/docker-compose.yml down || true

# TODO: Valuate if to run pre-install script (for example to update the OS) or directly the setup scripts
# TODO: Valuate if to run deps-install script (for example to install docker) or directly the setup scripts
bash $TMP_DIR/install/scripts/1-deps-install.sh

#1. Run setup scripts
bash $TMP_DIR/install/scripts/2-setup.sh

#2. Copy homelab files into installation directory
echo "Copying homelab files into $INSTALL_DIR ..."
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
