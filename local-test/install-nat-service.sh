#!/bin/bash
# Install NAT service to auto-apply rules on macOS startup

set -e

PLIST_FILE="com.multipass.nat.plist"
INSTALL_PATH="/Library/LaunchDaemons/com.multipass.nat.plist"

echo "Installing Multipass NAT service..."
echo ""

# Copy plist to LaunchDaemons
echo "1. Copying plist to $INSTALL_PATH..."
sudo cp "$PLIST_FILE" "$INSTALL_PATH"
sudo chown root:wheel "$INSTALL_PATH"
sudo chmod 644 "$INSTALL_PATH"

# Load the service
echo "2. Loading the service..."
sudo launchctl load "$INSTALL_PATH"

echo ""
echo "✓ NAT service installed successfully!"
echo ""
echo "The NAT rules will now be applied automatically on system startup."
echo ""
echo "To verify the service is loaded:"
echo "  sudo launchctl list | grep multipass.nat"
echo ""
echo "To manually start the service:"
echo "  sudo launchctl start com.multipass.nat"
echo ""
echo "To uninstall:"
echo "  sudo launchctl unload $INSTALL_PATH"
echo "  sudo rm $INSTALL_PATH"
echo ""
