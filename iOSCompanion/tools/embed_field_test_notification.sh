#!/bin/sh
# Copies the field-test notification extension into the app only when asked.
# Default is off so a free Apple ID signing pass does not register another App ID.
set -eu
FLAG="${PATRICK_FIELD_TEST_NOTIFICATION_EXTENSION:-NO}"
if [ "$FLAG" != "YES" ]; then
  echo "patrick field-test notification extension: not embedded (PATRICK_FIELD_TEST_NOTIFICATION_EXTENSION=$FLAG)"
  exit 0
fi
SOURCE="${BUILT_PRODUCTS_DIR}/PatrickFieldTestNotification.appex"
DEST="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/PlugIns"
if [ ! -d "$SOURCE" ]; then
  echo "error: field-test notification extension was not built at $SOURCE" >&2
  exit 1
fi
mkdir -p "$DEST"
rm -rf "${DEST}/PatrickFieldTestNotification.appex"
cp -R "$SOURCE" "${DEST}/"
echo "patrick field-test notification extension: embedded"
