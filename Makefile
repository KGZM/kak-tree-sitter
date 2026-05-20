# kak-tree-sitter uses dlopen to load grammar .so files at runtime.
# Static musl stubs out dlopen → grammars cannot load. Use glibc targets.
CARGO_TARGET_x86_64-linux  = x86_64-unknown-linux-gnu
CARGO_TARGET_aarch64-linux = aarch64-unknown-linux-gnu

DIST_TARGET = unknown-linux

# Language set compiled into every release artifact.
# Grammars are compiled from pinned upstream commits (see ktsctl default-config).
# To add a language: edit this list and cut a new release.
# Full language set. Languages not in ktsctl defaults are defined in config/grammars.toml.
# ktsctl merges config/grammars.toml with its built-in defaults at sync time.
# To add a language: add it here + add its grammar config to config/grammars.toml if needed.
# Languages from ktsctl defaults: bash, c, cpp, css, diff, fish, javascript, kdl,
#   markdown, markdown.inline, python, rust, toml, typescript
# Languages from config/grammars.toml: go, json, zig, janet-simple, clojure,
#   dockerfile, org, mermaid, git-config
#
# Excluded (C++ scanners that cause zig linker hangs):
#   yaml  — C++ scanner with -lstdc++; zig c++ link hangs in this environment.
#   sql   — C++ scanner (m-novikov); same issue.
#   html  — C++ scanner; same issue.
# Excluded (other):
#   kak   — no tree-sitter grammar exists upstream.
#   janet — use janet-simple instead (more robust, same helix queries).
# All grammars from helix languages.toml, minus C++ scanners.
# Selection of which to LOAD at runtime is handled by anima — ship everything.
#
# Excluded (C++ scanners that hang zig linker): cmake html ruby vue yaml sql
# Sources: ktsctl defaults + config/grammars.toml (helix-derived, pinned commits)
LANGUAGES = \
  ada adl agda amber astro awk bash bass beancount bibtex bicep bitbake \
  blade blueprint c c-sharp cairo capnp cel circom clojure comment cpon \
  cpp css csv cue cylc d dart dbml devicetree dhall diff djot dockerfile \
  dot dtd earthfile edoc eex elisp elixir elm elvish embedded-template \
  erlang esdl fga fidl fish forth fortran fsharp gas gdscript gemini \
  gherkin ghostty git-commit git-config git-rebase gitattributes gitignore \
  gleam glimmer glsl gn go godot-resource gomod gotmpl gowork gpr graphql \
  gren groovy hare haskell haskell-persistent hcl heex hocon hoon hosts \
  hurl hyprlang iex ini ink inko janet-simple java javascript jinja2 \
  jjdescription jq jsdoc json json5 jsonnet julia just kdl koka kotlin \
  koto latex ld ldif lean ledger llvm llvm-mir log lpf lua make markdoc \
  markdown markdown.inline matlab mermaid meson mojo move nasm nginx \
  nickel nim nix nu ocaml ocaml-interface odin ohm opencl openscad org \
  pascal passwd pem perl pest php php-only pkl po pod ponylang powershell \
  prisma proto prql purescript python ql qmljs query quint r regex rego \
  rescript robot ron rst rust scala scheme scss slint smali smithy sml \
  snakemake solidity spade spicedb sshclientconfig strace supercollider \
  svelte sway swift t32 tablegen tact task tcl teal templ tera textproto \
  thrift todotxt toml tsx twig typescript typespec typst ungrammar unison \
  uxntal v vala vento verilog vhdl vhs wast wat wgsl wit wren xit xml \
  xtc yara yuck zig

# Scratch dirs for grammar compilation — per-target to avoid collisions.
# Kept inside the repo so the source cache survives across sessions.
# Both are gitignored.
GRAMMAR_BUILD_DIR = $(CURDIR)/.grammar-build/$(DIST_TARGET)
GRAMMAR_DATA_DIR  = $(CURDIR)/.grammar-data/$(DIST_TARGET)

# Zig cross-compilation target for grammar .so files.
# Grammars are architecture-specific and must match the target runtime.
# Grammars are dlopen'd by kak-tree-sitter (glibc binary), so compile them
# as glibc shared objects. glibc and musl .so ABI is compatible for simple
# tree-sitter parsers, but using the same libc avoids any symbol issues.
ZIG_TARGET_x86_64-linux  = x86_64-linux-gnu
ZIG_TARGET_aarch64-linux = aarch64-linux-gnu
ZIG_TARGET = $(ZIG_TARGET_$(DIST_TARGET))

.PHONY: package clean-grammars

# Remove only compiled grammar outputs, preserving the source cache.
# Use this instead of wiping GRAMMAR_BUILD_DIR — re-cloning helix takes minutes.
clean-grammars:
	rm -rf $(GRAMMAR_DATA_DIR)/kak-tree-sitter/grammars
	rm -rf $(GRAMMAR_DATA_DIR)/kak-tree-sitter/queries
	rm -rf dist/$(DIST_TARGET)/share/kak-tree-sitter/grammars
	rm -rf dist/$(DIST_TARGET)/share/kak-tree-sitter/kts-queries
	@echo "cleaned compiled grammars; source cache in $(GRAMMAR_BUILD_DIR) preserved"

# Build binaries, compile grammars for LANGUAGES, stage everything into dist/$(DIST_TARGET)/.
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
	# For x86_64 host build: cargo build (native glibc).
	# For aarch64 cross: cargo zigbuild with gnu target (glibc, supports dlopen).
	cargo zigbuild --release --locked \
		--target $(CARGO_TARGET_$(DIST_TARGET)) \
		--features kak-tree-sitter/direct-unix-socket \
		-p kak-tree-sitter -p ktsctl
	# For cross builds, also build the host ktsctl for grammar compilation.
	# ktsctl orchestrates grammar fetch+compile by calling "cc" (our zig wrapper).
	# The aarch64 ktsctl binary can't run on the host (needs aarch64 glibc); the
	# host ktsctl can, and the cc wrapper handles cross-targeting the .so files.
	@if [ "$(DIST_TARGET)" != "x86_64-linux" ]; then \
		cargo zigbuild --release --locked \
			--target x86_64-unknown-linux-gnu \
			-p ktsctl; \
	fi
	# 2. compile grammars using ktsctl (host binary for cross builds)
	# ktsctl hardcodes "cc" as the compiler command (ignores CC env var).
	# Wrap zig cc/c++ as cc on PATH so ktsctl finds the right toolchain.
	# IMPORTANT: GRAMMAR_BUILD_DIR is intentionally NOT cleaned between runs.
	# It caches cloned grammar and helix repos. Wiping it forces a full re-clone
	# of helix (162MB) which takes many minutes. Only wipe GRAMMAR_DATA_DIR
	# (compiled .so files) to force recompilation without losing the source cache.
	@mkdir -p $(GRAMMAR_BUILD_DIR) $(GRAMMAR_DATA_DIR) $(GRAMMAR_BUILD_DIR)/bin
	# ktsctl calls "cc" for both compile and link steps.
	# Compile: zig drops files when extensions are mixed (.c + .cc), so compile each
	#          source file individually, dispatching zig cc (.c) or zig c++ (.cc/.cpp).
	# Link:    "zig cc -lc++" recompiles all of libc++ from source — very slow.
	#          Always use "zig c++" for link steps (no -c flag); it bundles libc++
	#          automatically without recompiling it. Also strip -lstdc++/-lc++ since
	#          zig c++ handles C++ runtime implicitly.
	printf '%s\n' \
		'#!/bin/sh' \
		'# Wrapper around zig cc/c++ for ktsctl grammar compilation.' \
		'# Cross-compilation target is baked in at generation time.' \
		'TARGET=$(ZIG_TARGET)' \
		'compiling=0; needs_cxx=0; flags=""; sources=""' \
		'for arg; do' \
		'  case "$$arg" in' \
		'    -c)            compiling=1; flags="$$flags $$arg" ;;' \
		'    -lstdc++|-lc++) needs_cxx=1 ;;' \
		'    *.c|*.cc|*.cpp|*.cxx|*.C) sources="$$sources $$arg" ;;' \
		'    *)              flags="$$flags $$arg" ;;' \
		'  esac' \
		'done' \
		'if [ "$$compiling" -eq 0 ]; then' \
		'  if [ "$$needs_cxx" -eq 1 ]; then' \
		'    exec zig c++ -target $$TARGET $$flags $$sources' \
		'  else' \
		'    exec zig cc -target $$TARGET $$flags $$sources' \
		'  fi' \
		'fi' \
		'[ -z "$$sources" ] && exec zig cc -target $$TARGET "$$@"' \
		'for src in $$sources; do' \
		'  case "$$src" in' \
		'    *.cc|*.cpp|*.cxx|*.C) cmd="zig c++" ;;' \
		'    *) cmd="zig cc" ;;' \
		'  esac' \
		'  $$cmd -target $$TARGET $$flags "$$src" || exit $$?' \
		'done' \
		> $(GRAMMAR_BUILD_DIR)/bin/cc
	chmod +x $(GRAMMAR_BUILD_DIR)/bin/cc
	env \
		XDG_RUNTIME_DIR=$(GRAMMAR_BUILD_DIR) \
		XDG_DATA_HOME=$(GRAMMAR_DATA_DIR) \
		PATH=$(GRAMMAR_BUILD_DIR)/bin:$(CURDIR)/target/x86_64-unknown-linux-gnu/release:$(CURDIR)/target/$(CARGO_TARGET_$(DIST_TARGET))/release:/usr/bin:/usr/local/bin:$$PATH \
	sh -c ' \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync ada adl agda amber astro awk bash bass beancount bibtex bicep bitbake blade blueprint c & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync c-sharp cairo capnp cel circom clojure comment cpon cpp css csv cue cylc d dart & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync dbml devicetree dhall diff djot dockerfile dot dtd earthfile edoc eex elisp elixir elm elvish & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync embedded-template erlang esdl fga fidl fish forth fortran fsharp gas gdscript gemini gherkin ghostty git-commit & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync git-config git-rebase gitattributes gitignore gleam glimmer glsl gn go godot-resource gomod gotmpl gowork gpr graphql & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync gren groovy hare haskell haskell-persistent hcl heex hocon hoon hosts hurl hyprlang iex ini ink & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync inko janet-simple java javascript jinja2 jjdescription jq jsdoc json json5 jsonnet julia just kdl koka & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync kotlin koto latex ld ldif lean ledger llvm llvm-mir log lpf lua make markdoc markdown & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync markdown.inline matlab mermaid meson mojo move nasm nginx nickel nim nix nu ocaml ocaml-interface odin & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync ohm opencl openscad org pascal passwd pem perl pest php php-only pkl po pod ponylang & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync powershell prisma proto prql purescript python ql qmljs query quint r regex rego rescript robot & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync ron rst rust scala scheme scss slint smali smithy sml snakemake solidity spade spicedb sshclientconfig & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync strace supercollider svelte sway swift t32 tablegen tact task tcl teal templ tera textproto thrift & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync todotxt toml tsx twig typescript typespec typst ungrammar unison uxntal v vala vento verilog vhdl & \
		ktsctl --verbose --config $(CURDIR)/config/grammars.toml sync vhs wast wat wgsl wit wren xit xml xtc yara yuck zig & \
		wait \
	'
	# 3. stage into dist/
	rm -rf dist/$(DIST_TARGET)
	mkdir -p dist/$(DIST_TARGET)/bin dist/$(DIST_TARGET)/share/kak-tree-sitter
	cp target/$(CARGO_TARGET_$(DIST_TARGET))/release/kak-tree-sitter \
	   target/$(CARGO_TARGET_$(DIST_TARGET))/release/ktsctl \
	   dist/$(DIST_TARGET)/bin/
	cp -r runtime/queries    dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r runtime/completions dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r $(GRAMMAR_DATA_DIR)/kak-tree-sitter/grammars \
	      dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r $(GRAMMAR_DATA_DIR)/kak-tree-sitter/queries \
	      dist/$(DIST_TARGET)/share/kak-tree-sitter/kts-queries
	@printf 'packaged: dist/%s/  (kak-tree-sitter %s, ktsctl %s, %d grammars)\n' \
		"$(DIST_TARGET)" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/kak-tree-sitter | awk '{print $$5}')" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/ktsctl | awk '{print $$5}')" \
		"$$(ls dist/$(DIST_TARGET)/share/kak-tree-sitter/grammars 2>/dev/null | wc -l)"
