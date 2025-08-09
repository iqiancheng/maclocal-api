#!/bin/bash

# Create AFM Distribution Package
# This script creates a redistributable package with the afm binary

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 Creating AFM Distribution Package${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Get version from binary or default
VERSION=$(git describe --tags --always 2>/dev/null || echo "v0.4.0")
ARCH=$(uname -m)
DIST_NAME="afm-${VERSION}-${ARCH}"

echo -e "${BLUE}ℹ️  Package: ${DIST_NAME}${NC}"
echo -e "${BLUE}ℹ️  Architecture: ${ARCH}${NC}"
echo ""

# Build release if needed
if [[ ! -f ".build/release/afm" ]]; then
    echo -e "${YELLOW}⚠️  Release binary not found. Building...${NC}"
    swift build -c release
    echo ""
fi

# Create distribution directory
DIST_DIR="dist/${DIST_NAME}"
echo -e "${BLUE}📁 Creating distribution directory: ${DIST_DIR}${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Copy binary
echo -e "${BLUE}📋 Copying binary...${NC}"
cp .build/release/afm "$DIST_DIR/"

# Create portable install script
echo -e "${BLUE}📝 Creating portable install script...${NC}"
cat > "$DIST_DIR/install.sh" << 'EOF'
#!/bin/bash

# AFM Portable Installer
# This script installs the afm binary from this package

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"

echo "🚀 Installing AFM from portable package..."
echo ""

# Check if binary exists
if [[ ! -f "$SCRIPT_DIR/afm" ]]; then
    echo "❌ Error: afm binary not found in package"
    exit 1
fi

# Create install directory if needed
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Creating $INSTALL_DIR directory..."
    sudo mkdir -p "$INSTALL_DIR"
fi

# Install binary
echo "📦 Installing afm to $INSTALL_DIR..."
if [[ -w "$INSTALL_DIR" ]]; then
    cp "$SCRIPT_DIR/afm" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/afm"
else
    sudo cp "$SCRIPT_DIR/afm" "$INSTALL_DIR/"
    sudo chmod +x "$INSTALL_DIR/afm"
fi

echo "✅ Installation complete!"
echo ""
echo "Usage: afm --help"
echo "Start server: afm --port 9999"
echo ""
echo "Note: Requires macOS 15.1+ and Apple Intelligence enabled"
EOF

chmod +x "$DIST_DIR/install.sh"

# Create README
echo -e "${BLUE}📖 Creating README...${NC}"
cat > "$DIST_DIR/README.md" << EOF
# AFM - Apple Foundation Models API

A high-performance server that exposes Apple's Foundation Models through an OpenAI-compatible API.

## Quick Start

1. **Install**: Run \`./install.sh\` (requires admin privileges)
2. **Start**: Run \`afm --port 9999\`
3. **Use**: Send requests to \`http://localhost:9999/v1/chat/completions\`

## Requirements

- **macOS**: 15.1+ (Sequoia) recommended
- **Hardware**: Apple Silicon Mac (M1/M2/M3/M4)
- **Apple Intelligence**: Must be enabled in System Settings

## Usage

\`\`\`bash
# Show help
afm --help

# Start server on port 8080
afm --port 8080

# Enable verbose logging
afm --verbose

# Disable streaming responses
afm --no-streaming
\`\`\`

## API Endpoints

- **POST** \`/v1/chat/completions\` - Chat completions (OpenAI compatible)
- **GET** \`/v1/models\` - List available models
- **GET** \`/health\` - Health check

## Features

- ✅ OpenAI-compatible API
- ⚡ ChatGPT-style smooth streaming
- 🎛️ CLI controls for streaming
- 🛑 Proper CTRL-C shutdown
- 📝 Markdown-aware streaming (preserves code blocks)
- 🔧 Configurable ports and logging

## Example Request

\`\`\`bash
curl -X POST http://localhost:9999/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "foundation",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ],
    "stream": true
  }'
\`\`\`

---

Package: ${DIST_NAME}
Architecture: ${ARCH}
Built: $(date)
EOF

# Create tarball
echo -e "${BLUE}📦 Creating tarball...${NC}"
cd dist
tar -czf "${DIST_NAME}.tar.gz" "${DIST_NAME}"
cd ..

# Cleanup
echo -e "${BLUE}🧹 Cleaning up...${NC}"
rm -rf "$DIST_DIR"

echo ""
echo -e "${GREEN}✅ Distribution package created: dist/${DIST_NAME}.tar.gz${NC}"
echo ""
echo -e "${BLUE}📋 Package contents:${NC}"
echo "  • afm binary ($(du -h .build/release/afm | cut -f1))"
echo "  • install.sh (portable installer)"
echo "  • README.md (documentation)"
echo ""
echo -e "${BLUE}🚀 Usage:${NC}"
echo "  1. Extract: tar -xzf dist/${DIST_NAME}.tar.gz"
echo "  2. Install: cd ${DIST_NAME} && ./install.sh"
echo ""
echo -e "${GREEN}🎉 Ready for distribution!${NC}"