# kak-tree-sitter uses dlopen to load grammar .so files at runtime.
# Static musl stubs out dlopen → grammars cannot load. Use glibc targets.
CARGO_TARGET_x86_64-linux  = x86_64-unknown-linux-gnu
CARGO_TARGET_aarch64-linux = aarch64-unknown-linux-gnu

DIST_TARGET = unknown-linux

.PHONY: package

# Build binaries and stage everything into dist/$(DIST_TARGET)/.
# No network access or C compiler required at runtime.
#
# Usage:
#   make package DIST_TARGET=x86_64-linux
#   make package DIST_TARGET=aarch64-linux
package:
	@test "$(DIST_TARGET)" != "unknown-linux" || \
		{ echo "usage: make package DIST_TARGET=x86_64-linux"; exit 1; }
	# 1. compile binaries
	# kak-tree-sitter uses dlopen for grammars → must be glibc (not static musl).
	# direct-unix-socket: send responses directly to kak session socket instead of
	# spawning "kak -p session" (avoids subprocess PATH/permission issues).
	cargo zigbuild --release --locked \
		--target $(CARGO_TARGET_$(DIST_TARGET)) \
		--features kak-tree-sitter/direct-unix-socket \
		-p kak-tree-sitter -p ktsctl
	# 2. stage into dist/
	rm -rf dist/$(DIST_TARGET)
	mkdir -p dist/$(DIST_TARGET)/bin dist/$(DIST_TARGET)/share/kak-tree-sitter
	cp target/$(CARGO_TARGET_$(DIST_TARGET))/release/kak-tree-sitter \
	   target/$(CARGO_TARGET_$(DIST_TARGET))/release/ktsctl \
	   dist/$(DIST_TARGET)/bin/
	cp -r runtime/queries     dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r runtime/completions dist/$(DIST_TARGET)/share/kak-tree-sitter/
	@printf 'packaged: dist/%s/  (kak-tree-sitter %s, ktsctl %s)\n' \
		"$(DIST_TARGET)" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/kak-tree-sitter | awk '{print $$5}')" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/ktsctl | awk '{print $$5}')"
