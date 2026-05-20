# kak-tree-sitter uses dlopen to load grammar .so files at runtime.
# Static musl stubs out dlopen → grammars cannot load. Use glibc targets.
CARGO_TARGET_x86_64-linux  = x86_64-unknown-linux-gnu
CARGO_TARGET_aarch64-linux = aarch64-unknown-linux-gnu

DIST_TARGET = unknown-linux

# Languages to sync helix queries for.
# Grammars are NOT compiled here — they come from kgzm/grammars.
# To add a language: add it here and ensure kgzm/grammars ships its .so.
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

# Query cache — per-target to avoid collisions.
# Kept inside the repo so the helix source clone survives across builds.
QUERY_DATA_DIR = $(CURDIR)/.query-data/$(DIST_TARGET)

.PHONY: package clean-queries

clean-queries:
	rm -rf $(QUERY_DATA_DIR)/kak-tree-sitter/queries
	rm -rf dist/$(DIST_TARGET)/share/kak-tree-sitter/kts-queries
	@echo "cleaned query cache"

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
	cargo zigbuild --release --locked \
		--target $(CARGO_TARGET_$(DIST_TARGET)) \
		--features kak-tree-sitter/direct-unix-socket \
		-p kak-tree-sitter -p ktsctl
	# For cross builds, also build host ktsctl to run query sync on the CI runner.
	@if [ "$(DIST_TARGET)" != "x86_64-linux" ]; then \
		cargo zigbuild --release --locked \
			--target x86_64-unknown-linux-gnu \
			-p ktsctl; \
	fi
	# 2. sync helix queries via ktsctl (grammars skipped — source = "bundled")
	@mkdir -p $(QUERY_DATA_DIR)
	env \
		XDG_RUNTIME_DIR=$(QUERY_DATA_DIR) \
		XDG_DATA_HOME=$(QUERY_DATA_DIR) \
		PATH=$(CURDIR)/target/x86_64-unknown-linux-gnu/release:$(CURDIR)/target/$(CARGO_TARGET_$(DIST_TARGET))/release:/usr/bin:/usr/local/bin:$$PATH \
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
	cp -r runtime/queries     dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r runtime/completions dist/$(DIST_TARGET)/share/kak-tree-sitter/
	cp -r $(QUERY_DATA_DIR)/kak-tree-sitter/queries \
	      dist/$(DIST_TARGET)/share/kak-tree-sitter/kts-queries
	@printf 'packaged: dist/%s/  (kak-tree-sitter %s, ktsctl %s)\n' \
		"$(DIST_TARGET)" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/kak-tree-sitter | awk '{print $$5}')" \
		"$$(ls -lh dist/$(DIST_TARGET)/bin/ktsctl | awk '{print $$5}')"
