#!/usr/bin/env bash
# install-mas-profile.sh
# Fetches and installs the MAC_APP_STORE provisioning profile from App Store Connect.
# Prints the profile name to stdout (for CI to capture as PP_NAME).
#
# Usage:
#   ./scripts/install-mas-profile.sh
#
# Prerequisites:
#   brew install asccli jq
#   export ASC_KEY_ID="<your-key-id>"
#   export ASC_ISSUER_ID="<your-issuer-id>"
#   export ASC_PRIVATE_KEY="$(cat ~/.asc/<key-id>.p8)"

set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.tddworks.claudebar}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Verify asc credentials are set
if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_PRIVATE_KEY:-}" ]; then
  echo "Error: ASC credentials not set. Export before running:" >&2
  echo "" >&2
  echo "  export ASC_KEY_ID=\"<your-key-id>\"" >&2
  echo "  export ASC_ISSUER_ID=\"<your-issuer-id>\"" >&2
  echo "  export ASC_PRIVATE_KEY=\"\$(cat ~/.asc/<key-id>.p8)\"" >&2
  exit 1
fi

echo "==> Resolving bundle ID for $BUNDLE_ID..." >&2
BUNDLE_ID_ID=$(asc bundle-ids list --identifier "$BUNDLE_ID" --platform macos \
  | jq -r '.data[0].id')

if [ -z "$BUNDLE_ID_ID" ] || [ "$BUNDLE_ID_ID" = "null" ]; then
  echo "Error: Bundle ID '$BUNDLE_ID' not found in App Store Connect" >&2
  exit 1
fi
echo "    Bundle ID resource: $BUNDLE_ID_ID" >&2

echo "==> Fetching MAC_APP_STORE profile..." >&2
PROFILE_JSON=$(asc profiles list --bundle-id-id "$BUNDLE_ID_ID" --type MAC_APP_STORE)
PROFILE_CONTENT=$(echo "$PROFILE_JSON" | jq -r '.data[0].profileContent // .data[0].attributes.profileContent')
PP_NAME=$(echo "$PROFILE_JSON" | jq -r '.data[0].name // .data[0].attributes.name')

if [ -z "$PROFILE_CONTENT" ] || [ "$PROFILE_CONTENT" = "null" ]; then
  echo "Error: No MAC_APP_STORE profile found for $BUNDLE_ID" >&2
  echo "Create one with:" >&2
  echo "  asc profiles create --name 'ClaudeBar Mac App Store' --type MAC_APP_STORE \\" >&2
  echo "    --bundle-id-id $BUNDLE_ID_ID --certificate-ids <cert-id>" >&2
  exit 1
fi
echo "    Profile: $PP_NAME (${#PROFILE_CONTENT} base64 chars)" >&2

echo "==> Decoding and installing..." >&2
PP_PATH="$WORK_DIR/mas.provisionprofile"
# -A: treat entire input as one line (ASC API returns non-line-wrapped base64)
printf '%s' "$PROFILE_CONTENT" > "$WORK_DIR/profile.b64"
openssl base64 -d -A -in "$WORK_DIR/profile.b64" -out "$PP_PATH"
echo "    Decoded size: $(wc -c < "$PP_PATH") bytes" >&2

security cms -D -i "$PP_PATH" > "$WORK_DIR/profile.plist"
PP_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$WORK_DIR/profile.plist")
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PP_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PP_UUID.provisionprofile"


PP_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' "$WORK_DIR/profile.plist")
echo "    UUID: $PP_UUID" >&2
echo "    Installed: ~/Library/MobileDevice/Provisioning Profiles/$PP_UUID.provisionprofile" >&2

# Print profile name to stdout for CI capture: PP_NAME=$(./scripts/install-mas-profile.sh)
echo "$PP_NAME"
