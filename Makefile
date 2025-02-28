# GIT_LFS_SHA is the '--short'-form SHA1 of the current revision of Git LFS.
GIT_LFS_SHA ?= $(shell git rev-parse --short HEAD)
# VERSION is the longer-form describe output of the current revision of Git LFS,
# used for identifying intermediate releases.
#
# If Git LFS is being built for a published release, VERSION and GIT_LFS_SHA
# should be identical.
VERSION ?= $(shell git describe HEAD)

# GO is the name of the 'go' binary used to compile Git LFS.
GO ?= go

# GO_TEST_EXTRA_ARGS are extra arguments given to invocations of 'go test'.
#
# Examples include:
#
# 	make test GO_TEST_EXTRA_ARGS=-v
# 	make test GO_TEST_EXTRA_ARGS='-run TestMyExample'
GO_TEST_EXTRA_ARGS =

# BUILTIN_LD_FLAGS are the internal flags used to pass to the linker. By default
# the config.GitCommit variable is always set via this variable, and
# DWARF-stripping is enabled unless DWARF=YesPlease.
BUILTIN_LD_FLAGS =
ifneq ("$(VENDOR)","")
BUILTIN_LD_FLAGS += -X github.com/git-lfs/git-lfs/config.Vendor=$(VENDOR)
endif
BUILTIN_LD_FLAGS += -X github.com/git-lfs/git-lfs/config.GitCommit=$(GIT_LFS_SHA)
ifneq ("$(DWARF)","YesPlease")
BUILTIN_LD_FLAGS += -s
BUILTIN_LD_FLAGS += -w
endif
# EXTRA_LD_FLAGS are given by the caller, and are passed to the Go linker after
# BUILTIN_LD_FLAGS are processed. By default the system LDFLAGS are passed.
ifdef LDFLAGS
EXTRA_LD_FLAGS ?= -extldflags ${LDFLAGS}
endif
# LD_FLAGS is the union of the above two BUILTIN_LD_FLAGS and EXTRA_LD_FLAGS.
LD_FLAGS = $(BUILTIN_LD_FLAGS) $(EXTRA_LD_FLAGS)

# BUILTIN_GC_FLAGS are the internal flags used to pass compiler.
BUILTIN_GC_FLAGS ?= all=-trimpath="$$HOME"
# EXTRA_GC_FLAGS are the caller-provided flags to pass to the compiler.
EXTRA_GC_FLAGS =
# GC_FLAGS are the union of the above two BUILTIN_GC_FLAGS and EXTRA_GC_FLAGS.
GC_FLAGS = $(BUILTIN_GC_FLAGS) $(EXTRA_GC_FLAGS)

ASM_FLAGS ?= all=-trimpath="$$HOME"

# TRIMPATH contains arguments to be passed to go to strip paths on Go 1.13 and
# newer.
TRIMPATH ?= $(shell [ "$$($(GO) version | awk '{print $$3}' | sed -e 's/^[^.]*\.//;s/\..*$$//;')" -ge 13 ] && echo -trimpath)

# RONN is the name of the 'ronn' program used to generate man pages.
RONN ?= ronn
# RONN_EXTRA_ARGS are extra arguments given to the $(RONN) program when invoked.
RONN_EXTRA_ARGS ?=

# GREP is the name of the program used for regular expression matching, or
# 'grep' if unset.
GREP ?= grep
# XARGS is the name of the program used to turn stdin into program arguments, or
# 'xargs' if unset.
XARGS ?= xargs

# GOIMPORTS is the name of the program formatter used before compiling.
GOIMPORTS ?= goimports
# GOIMPORTS_EXTRA_OPTS are the default options given to the $(GOIMPORTS)
# program.
GOIMPORTS_EXTRA_OPTS ?= -w -l

TAR_XFORM_ARG ?= $(shell tar --version | grep -q 'GNU tar' && echo '--xform' || echo '-s')
TAR_XFORM_CMD ?= $(shell tar --version | grep -q 'GNU tar' && echo 's')

# CERT_SHA1 is the SHA-1 hash of the Windows code-signing cert to use.  The
# actual signature is made with SHA-256.
CERT_SHA1 ?= 824455beeb23fe270e756ca04ec8e902d19c62aa

# CERT_FILE is the PKCS#12 file holding the certificate.
CERT_FILE ?=

# CERT_PASS is the password for the certificate.  It must not contain
# double-quotes.
CERT_PASS ?=

# CERT_ARGS are additional arguments to pass when signing Windows binaries.
ifneq ("$(CERT_FILE)$(CERT_PASS)","")
CERT_ARGS ?= -f "$(CERT_FILE)" -p "$(CERT_PASS)"
else
CERT_ARGS ?= -sha1 $(CERT_SHA1)
endif

# DARWIN_CERT_ID is a portion of the common name of the signing certificatee.
DARWIN_CERT_ID ?=

# DARWIN_KEYCHAIN_ID is the name of the keychain (with suffix) where the
# certificate is located.
DARWIN_KEYCHAIN_ID ?= CI.keychain

# SOURCES is a listing of all .go files in this and child directories, excluding
# that in vendor.
SOURCES = $(shell find . -type f -name '*.go' | grep -v vendor)

# MSGFMT is the GNU gettext msgfmt binary.
MSGFMT ?= msgfmt

# PO is a list of all the po (gettext source) files.
PO = $(wildcard po/*.po)

# MO is a list of all the mo (gettext compiled) files to be built.
MO = $(patsubst po/%.po,po/build/%.mo,$(PO))

# XGOTEXT is the string extractor for gotext.
XGOTEXT ?= xgotext

# PKGS is a listing of packages that are considered to be a part of Git LFS, and
# are used in package-specific commands, such as the 'make test' targets. For
# example:
#
# 	make test                               # run 'go test' in all packages
# 	make PKGS='config git/githistory' test  # run 'go test' in config and
# 	                                        # git/githistory
#
# By default, it is a listing of all packages in Git LFS. When new packages (or
# sub-packages) are created, they should be added here.
ifndef PKGS
PKGS =
PKGS += commands
PKGS += config
PKGS += creds
PKGS += errors
PKGS += filepathfilter
PKGS += fs
PKGS += git
PKGS += git/gitattr
PKGS += git/githistory
PKGS += git
PKGS += lfs
PKGS += lfsapi
PKGS += lfshttp
PKGS += locking
PKGS += ssh
PKGS += subprocess
PKGS += tasklog
PKGS += tools
PKGS += tools/humanize
PKGS += tools/kv
PKGS += tr
PKGS += tq
endif

# X is the platform-specific extension for Git LFS binaries. It is automatically
# set to .exe on Windows, and the empty string on all other platforms. It may be
# overridden.
#
# BUILD_MAIN is the main ".go" file that contains func main() for Git LFS. On
# macOS and other non-Windows platforms, it is required that a specific
# entrypoint be given, hence the below conditional. On Windows, it is required
# that an entrypoint not be given so that goversioninfo can successfully embed
# the resource.syso file (for more, see below).
ifeq ($(OS),Windows_NT)
X ?= .exe
BUILD_MAIN ?=
else
X ?=
BUILD_MAIN ?= ./git-lfs.go
endif

# BUILD is a macro used to build a single binary of Git LFS using the above
# LD_FLAGS and GC_FLAGS.
#
# It takes three arguments:
#
# 	$(1) - a valid GOOS value, or empty-string
# 	$(2) - a valid GOARCH value, or empty-string
# 	$(3) - an optional program extension. If $(3) is given as '-foo', then the
# 	       program will be written to bin/git-lfs-foo.
#
# It uses BUILD_MAIN as defined above to specify the entrypoint for building Git
# LFS.
BUILD = GOOS=$(1) GOARCH=$(2) \
	$(GO) build \
	-ldflags="$(LD_FLAGS)" \
	-gcflags="$(GC_FLAGS)" \
	-asmflags="$(ASM_FLAGS)" \
	$(TRIMPATH) \
	-o ./bin/git-lfs$(3) $(BUILD_MAIN)

# BUILD_TARGETS is the set of all platforms and architectures that Git LFS is
# built for.
BUILD_TARGETS = \
	bin/git-lfs-darwin-amd64 \
	bin/git-lfs-darwin-arm64 \
	bin/git-lfs-linux-arm \
	bin/git-lfs-linux-arm64 \
	bin/git-lfs-linux-amd64 \
	bin/git-lfs-linux-ppc64le \
	bin/git-lfs-linux-s390x \
	bin/git-lfs-linux-386 \
	bin/git-lfs-freebsd-amd64 \
	bin/git-lfs-freebsd-386 \
	bin/git-lfs-windows-amd64.exe \
	bin/git-lfs-windows-386.exe \
	bin/git-lfs-windows-arm64.exe

# mangen is a shorthand for ensuring that commands/mancontent_gen.go is kept
# up-to-date with the contents of docs/man/*.ronn.
.PHONY : mangen
mangen : commands/mancontent_gen.go

# commands/mancontent_gen.go is generated by running 'go generate' on package
# 'commands' of Git LFS. It depends upon the contents of the 'docs' directory
# and converts those manpages into code.
commands/mancontent_gen.go : $(wildcard docs/man/*.ronn)
	GOOS= GOARCH= $(GO) generate github.com/git-lfs/git-lfs/v3/commands

# trgen is a shorthand for ensuring that tr/tr_gen.go is kept up-to-date with
# the contents of po/build/*.mo.
.PHONY : trgen
trgen : tr/tr_gen.go

# tr/tr_gen.go is generated by running 'go generate' on package
# 'tr' of Git LFS. It depends upon the contents of the 'po' directory
# and converts the .mo files.
tr/tr_gen.go : $(MO)
	GOOS= GOARCH= $(GO) generate github.com/git-lfs/git-lfs/v3/tr

po/build:
	mkdir -p po/build

# These targets build the MO files.
po/build/%.mo: po/%.po po/build
	if command -v $(MSGFMT) >/dev/null 2>&1; \
	then \
		$(MSGFMT) -o $@ $<; \
	fi

po/i-reverse.po: po/default.pot
	script/gen-i-reverse $< $@

po/default.pot:
	if command -v $(XGOTEXT) >/dev/null 2>&1; \
	then \
		$(XGOTEXT) -in . -exclude .git,.github,vendor -out po -v; \
	fi

# Targets 'all' and 'build' build binaries of Git LFS for the above release
# matrix.
.PHONY : all build
all build : $(BUILD_TARGETS)

# The following bin/git-lfs-% targets make a single binary compilation of Git
# LFS for a specific operating system and architecture pair.
#
# They function by translating target names into arguments for the above BUILD
# builtin, and appending the appropriate suffix to the build target.
#
# On Windows, they also depend on the resource.syso target, which installs and
# embeds the versioninfo into the binary.
bin/git-lfs-darwin-amd64 : $(SOURCES) mangen trgen
	$(call BUILD,darwin,amd64,-darwin-amd64)
bin/git-lfs-darwin-arm64 : $(SOURCES) mangen trgen
	$(call BUILD,darwin,arm64,-darwin-arm64)
bin/git-lfs-linux-arm : $(SOURCES) mangen trgen
	GOARM=5 $(call BUILD,linux,arm,-linux-arm)
bin/git-lfs-linux-arm64 : $(SOURCES) mangen trgen
	$(call BUILD,linux,arm64,-linux-arm64)
bin/git-lfs-linux-amd64 : $(SOURCES) mangen trgen
	$(call BUILD,linux,amd64,-linux-amd64)
bin/git-lfs-linux-ppc64le : $(SOURCES) mangen trgen
	$(call BUILD,linux,ppc64le,-linux-ppc64le)
bin/git-lfs-linux-s390x : $(SOURCES) mangen trgen
	$(call BUILD,linux,s390x,-linux-s390x)
bin/git-lfs-linux-386 : $(SOURCES) mangen trgen
	$(call BUILD,linux,386,-linux-386)
bin/git-lfs-freebsd-amd64 : $(SOURCES) mangen trgen
	$(call BUILD,freebsd,amd64,-freebsd-amd64)
bin/git-lfs-freebsd-386 : $(SOURCES) mangen trgen
	$(call BUILD,freebsd,386,-freebsd-386)
bin/git-lfs-windows-amd64.exe : resource.syso $(SOURCES) mangen trgen
	$(call BUILD,windows,amd64,-windows-amd64.exe)
bin/git-lfs-windows-386.exe : resource.syso $(SOURCES) mangen trgen
	$(call BUILD,windows,386,-windows-386.exe)
bin/git-lfs-windows-arm64.exe : resource.syso $(SOURCES) mangen trgen
	$(call BUILD,windows,arm64,-windows-arm64.exe)

# .DEFAULT_GOAL sets the operating system-appropriate Git LFS binary as the
# default output of 'make'.
.DEFAULT_GOAL := bin/git-lfs$(X)

# bin/git-lfs targets the default output of Git LFS on non-Windows operating
# systems, and respects the build knobs as above.
bin/git-lfs : $(SOURCES) fmt mangen trgen
	$(call BUILD,$(GOOS),$(GOARCH),)

# bin/git-lfs.exe targets the default output of Git LFS on Windows systems, and
# respects the build knobs as above.
bin/git-lfs.exe : $(SOURCES) resource.syso mangen trgen
	$(call BUILD,$(GOOS),$(GOARCH),.exe)

# resource.syso installs the 'goversioninfo' command and uses it in order to
# generate a binary that has information included necessary to create the
# Windows installer.
#
# Generating a new resource.syso is a pure function of the contents in the
# prerequisites listed below.
resource.syso : \
versioninfo.json script/windows-installer/git-lfs-logo.bmp \
script/windows-installer/git-lfs-logo.ico \
script/windows-installer/git-lfs-wizard-image.bmp
	$(GO) generate

# RELEASE_TARGETS is the set of all release artifacts that we generate over a
# particular release. They each have a corresponding entry in BUILD_TARGETS as
# above.
#
# Unlike BUILD_TARGETS above, each of the below create a compressed directory
# containing the matching binary, as well as the contents of RELEASE_INCLUDES
# below.
#
# To build a specific release, execute the following:
#
# 	make bin/releases/git-lfs-darwin-amd64-$(git describe HEAD).tar.gz
#
# To build a specific release with a custom VERSION suffix, run the following:
#
# 	make VERSION=my-version bin/releases/git-lfs-darwin-amd64-my-version.tar.gz
RELEASE_TARGETS = \
	bin/releases/git-lfs-darwin-amd64-$(VERSION).zip \
	bin/releases/git-lfs-darwin-arm64-$(VERSION).zip \
	bin/releases/git-lfs-linux-arm-$(VERSION).tar.gz \
	bin/releases/git-lfs-linux-arm64-$(VERSION).tar.gz \
	bin/releases/git-lfs-linux-amd64-$(VERSION).tar.gz \
	bin/releases/git-lfs-linux-ppc64le-$(VERSION).tar.gz \
	bin/releases/git-lfs-linux-s390x-$(VERSION).tar.gz \
	bin/releases/git-lfs-linux-386-$(VERSION).tar.gz \
	bin/releases/git-lfs-freebsd-amd64-$(VERSION).tar.gz \
	bin/releases/git-lfs-freebsd-386-$(VERSION).tar.gz \
	bin/releases/git-lfs-windows-amd64-$(VERSION).zip \
	bin/releases/git-lfs-windows-386-$(VERSION).zip \
	bin/releases/git-lfs-windows-arm64-$(VERSION).zip \
	bin/releases/git-lfs-$(VERSION).tar.gz

# RELEASE_INCLUDES are the names of additional files that are added to each
# release artifact.
RELEASE_INCLUDES = README.md CHANGELOG.md man

# release is a phony target that builds all of the release artifacts, and then
# shows the SHA 256 signature of each.
#
# To build all of the release binaries for a given Git LFS release:
#
# 	make release
.PHONY : release
release : $(RELEASE_TARGETS)
	shasum -a 256 $(RELEASE_TARGETS)

# bin/releases/git-lfs-%-$(VERSION).tar.gz generates a gzip-compressed TAR of
# the non-Windows and non-macOS release artifacts.
#
# It includes all of RELEASE_INCLUDES, as well as script/install.sh.
bin/releases/git-lfs-%-$(VERSION).tar.gz : \
$(RELEASE_INCLUDES) bin/git-lfs-% script/install.sh
	@mkdir -p bin/releases
	tar $(TAR_XFORM_ARG) '$(TAR_XFORM_CMD)!bin/git-lfs-.*!git-lfs!' $(TAR_XFORM_ARG) '$(TAR_XFORM_CMD)!script/!!' -czf $@ $^

# bin/releases/git-lfs-darwin-$(VERSION).zip generates a ZIP compression of all
# of the macOS release artifacts.
#
# It includes all of the RELEASE_INCLUDES, as well as script/install.sh.
bin/releases/git-lfs-darwin-%-$(VERSION).zip : \
$(RELEASE_INCLUDES) bin/git-lfs-darwin-% script/install.sh
	dir=bin/releases/darwin-$* && \
	rm -f $@ && \
	mkdir -p $$dir && \
	cp -R $^ $$dir && mv $$dir/git-lfs-darwin-$* $$dir/git-lfs && \
	zip -j $@ $$dir/* && \
	zip -u $@ man/* && \
	$(RM) -r $$dir

# bin/releases/git-lfs-windows-$(VERSION).zip generates a ZIP compression of all
# of the Windows release artifacts.
#
# It includes all of the RELEASE_INCLUDES, and converts LF-style line endings to
# CRLF in the non-binary components of the artifact.
bin/releases/git-lfs-windows-%-$(VERSION).zip : $(RELEASE_INCLUDES) bin/git-lfs-windows-%.exe
	@mkdir -p bin/releases
	rm -f $@
	zip -j -l $@ $^
	zip -u $@ man/*

# bin/releases/git-lfs-$(VERSION).tar.gz generates a tarball of the source code.
#
# This is useful for third parties who wish to have a bit-for-bit identical
# source archive to download and verify cryptographically.
bin/releases/git-lfs-$(VERSION).tar.gz :
	git archive -o $@ --prefix=git-lfs-$(patsubst v%,%,$(VERSION))/ --format tar.gz $(VERSION)

# release-linux is a target that builds Linux packages. It must be run on a
# system with Docker that can run Linux containers.
.PHONY : release-linux
release-linux:
	./docker/run_dockers.bsh

# release-windows is a target that builds and signs Windows binaries.  It must
# be run on a Windows machine under Git Bash.
#
# You may sign with a different certificate by specifying CERT_ID.
.PHONY : release-windows
release-windows: bin/releases/git-lfs-windows-assets-$(VERSION).tar.gz

bin/releases/git-lfs-windows-assets-$(VERSION).tar.gz :
	$(RM) git-lfs-windows-*.exe
	@# Using these particular filenames is required for the Inno Setup script to
	@# work properly.
	$(MAKE) -B GOARCH=amd64 && cp ./bin/git-lfs.exe ./git-lfs-x64.exe
	$(MAKE) -B GOARCH=386 && cp ./bin/git-lfs.exe ./git-lfs-x86.exe
	$(MAKE) -B GOARCH=arm64 && cp ./bin/git-lfs.exe ./git-lfs-arm64.exe
	@echo Signing git-lfs-x64.exe
	@signtool.exe sign -debug -fd sha256 -tr http://timestamp.digicert.com -td sha256 $(CERT_ARGS) -v git-lfs-x64.exe
	@echo Signing git-lfs-x86.exe
	@signtool.exe sign -debug -fd sha256 -tr http://timestamp.digicert.com -td sha256 $(CERT_ARGS) -v git-lfs-x86.exe
	@echo Signing git-lfs-arm64.exe
	@signtool.exe sign -debug -fd sha256 -tr http://timestamp.digicert.com -td sha256 $(CERT_ARGS) -v git-lfs-arm64.exe
	iscc.exe script/windows-installer/inno-setup-git-lfs-installer.iss
	@# This file will be named according to the version number in the
	@# versioninfo.json, not according to $(VERSION).
	mv git-lfs-windows-*.exe git-lfs-windows.exe
	@echo Signing git-lfs-windows.exe
	@signtool.exe sign -debug -fd sha256 -tr http://timestamp.digicert.com -td sha256 $(CERT_ARGS) -v git-lfs-windows.exe
	mv git-lfs-x64.exe git-lfs-windows-amd64.exe
	mv git-lfs-x86.exe git-lfs-windows-386.exe
	mv git-lfs-arm64.exe git-lfs-windows-arm64.exe
	@# We use tar because Git Bash doesn't include zip.
	tar -czf $@ git-lfs-windows-amd64.exe git-lfs-windows-386.exe git-lfs-windows-arm64.exe git-lfs-windows.exe
	$(RM) git-lfs-windows-amd64.exe git-lfs-windows-386.exe git-lfs-windows-arm64.exe git-lfs-windows.exe

# release-windows-rebuild takes the archive produced by release-windows and
# incorporates the signed binaries into the existing zip archives.
.PHONY : release-windows-rebuild
release-windows-rebuild: bin/releases/git-lfs-windows-assets-$(VERSION).tar.gz
	temp=$$(mktemp -d); \
	file="$$PWD/$^"; \
		( \
			tar -C "$$temp" -xzf "$$file" && \
			for i in 386 amd64 arm64; do \
				cp "$$temp/git-lfs-windows-$$i.exe" "$$temp/git-lfs.exe" && \
				zip -d bin/releases/git-lfs-windows-$$i-$(VERSION).zip "git-lfs-windows-$$i.exe" && \
				zip -j -l bin/releases/git-lfs-windows-$$i-$(VERSION).zip  "$$temp/git-lfs.exe";  \
			done && \
			cp "$$temp/git-lfs-windows.exe" bin/releases/git-lfs-windows-$(VERSION).exe \
		); \
		status="$$?"; [ -n "$$temp" ] && $(RM) -r "$$temp"; exit "$$status"

# release-darwin is a target that builds and signs Darwin (macOS) binaries.  It must
# be run on a macOS machine with a suitable version of XCode.
#
# You may sign with a different certificate by specifying DARWIN_CERT_ID.
.PHONY : release-darwin
release-darwin: bin/releases/git-lfs-darwin-amd64-$(VERSION).zip bin/releases/git-lfs-darwin-arm64-$(VERSION).zip
	for i in $^; do \
		temp=$$(mktemp -d) && \
		( \
			unzip -d "$$temp" "$$i" && \
			codesign --keychain $(DARWIN_KEYCHAIN_ID) -s "$(DARWIN_CERT_ID)" --force --timestamp -vvvv --options runtime "$$temp/git-lfs" && \
			codesign -dvvv "$$temp/git-lfs" && \
			zip -j $$i "$$temp/git-lfs" && \
			codesign --keychain $(DARWIN_KEYCHAIN_ID) -s "$(DARWIN_CERT_ID)" --force --timestamp -vvvv --options runtime "$$i" && \
			codesign -dvvv "$$i" && \
			jq -e ".notarize.path = \"$$i\" | .apple_id.username = \"$(DARWIN_DEV_USER)\"" script/macos/manifest.json > "$$temp/manifest.json"; \
			for j in 1 2 3; \
			do \
				gon "$$temp/manifest.json" && break; \
			done; \
		); \
		status="$$?"; [ -n "$$temp" ] && $(RM) -r "$$temp"; [ "$$status" -eq 0 ] || exit "$$status"; \
	done

.PHONY : release-write-certificate
release-write-certificate:
	@echo "Writing certificate to $(CERT_FILE)"
	@echo "$$CERT_CONTENTS" | base64 --decode >"$$CERT_FILE"
	@printf 'Wrote %d bytes (SHA256 %s) to certificate file\n' $$(wc -c <"$$CERT_FILE") $$(shasum -ba 256 "$$CERT_FILE" | cut -d' ' -f1)

# release-import-certificate imports the given certificate into the macOS
# keychain "CI".  It is not generally recommended to run this on a user system,
# since it creates a new keychain and modifies the keychain search path.
.PHONY : release-import-certificate
release-import-certificate:
	@[ -n "$(CI)" ] || { echo "Don't run this target by hand." >&2; false; }
	@echo "Creating CI keychain"
	security create-keychain -p default CI.keychain
	security set-keychain-settings CI.keychain
	security unlock-keychain -p default CI.keychain
	@echo "Importing certificate from $(CERT_FILE)"
	@security import "$$CERT_FILE" -f pkcs12 -k CI.keychain -P "$$CERT_PASS" -A
	@echo "Verifying import and setting permissions"
	security list-keychains -s CI.keychain
	security default-keychain -s CI.keychain
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k default CI.keychain
	security find-identity -vp codesigning CI.keychain

# TEST_TARGETS is a list of all phony test targets. Each one of them corresponds
# to a specific kind or subset of tests to run.
TEST_TARGETS := test-bench test-verbose test-race
.PHONY : $(TEST_TARGETS) test
$(TEST_TARGETS) : test

# test-bench runs all Go benchmark tests, and nothing more.
test-bench : GO_TEST_EXTRA_ARGS=-run=__nothing__ -bench=.
# test-verbose runs all Go tests in verbose mode.
test-verbose : GO_TEST_EXTRA_ARGS=-v
# test-race runs all Go tests in race-detection mode.
test-race : GO_TEST_EXTRA_ARGS=-race

# test runs the Go tests with GO_TEST_EXTRA_ARGS in all specified packages,
# given by the PKGS variable.
#
# For example, a caller can invoke the race-detection tests in just the config
# package by running:
#
# 		make PKGS=config test-race
#
# Or in a series of packages, like:
#
# 		make PKGS="config lfsapi tools/kv" test-race
#
# And so on.
test : fmt $(.DEFAULT_GOAL)
	( \
		unset GIT_DIR; unset GIT_WORK_TREE; unset XDG_CONFIG_HOME; \
		tempdir="$$(mktemp -d)"; \
		export HOME="$$tempdir"; \
		export GIT_CONFIG_NOSYSTEM=1; \
		$(GO) test -count=1 $(GO_TEST_EXTRA_ARGS) $(addprefix ./,$(PKGS)); \
		RET=$$?; \
		chmod -R u+w "$$tempdir"; \
		rm -fr "$$tempdir"; \
		exit $$RET; \
	)

# integration is a shorthand for running 'make' in the 't' directory.
.PHONY : integration
integration : bin/git-lfs$(X)
	make -C t test

# go.sum is a lockfile based on the contents of go.mod.
go.sum : go.mod
	$(GO) mod verify >/dev/null

# vendor updates the go.sum-file, and installs vendored dependencies into
# the vendor/ sub-tree, removing sub-packages (listed below) that are unused by
# Git LFS as well as test code.
.PHONY : vendor
vendor : go.mod
	$(GO) mod vendor -v

# fmt runs goimports over all files in Git LFS (as defined by $(SOURCES) above),
# and replaces their contents with a formatted one in-place.
#
# If $(GOIMPORTS) does not exist, or isn't otherwise executable, this recipe
# still performs the linting sequence, but gracefully skips over running a
# non-existent command.
.PHONY : fmt
ifeq ($(shell test -x "`command -v $(GOIMPORTS)`"; echo $$?),0)
fmt : $(SOURCES) | lint
	@$(GOIMPORTS) $(GOIMPORTS_EXTRA_OPTS) $?;
else
fmt : $(SOURCES) | lint
	@echo "git-lfs: skipping fmt, no goimports found at \`$(GOIMPORTS)\` ..."
endif

# lint ensures that there are all dependencies outside of the standard library
# are vendored in via vendor (see: above).
.PHONY : lint
lint : $(SOURCES)
	@! $(GO) list -f '{{ join .Deps "\n" }}' . \
	| $(XARGS) $(GO) list -f \
		'{{ if and (not .Standard) (not .Module) }} \
			{{ .ImportPath }} \
		{{ end }}' \
	| $(GREP) -v "github.com/git-lfs/git-lfs" \
	| $(GREP) "."

# MAN_ROFF_TARGETS is a list of all ROFF-style targets in the man pages.
MAN_ROFF_TARGETS = man/git-lfs-checkout.1 \
  man/git-lfs-clean.1 \
  man/git-lfs-clone.1 \
  man/git-lfs-config.5 \
  man/git-lfs-env.1 \
  man/git-lfs-ext.1 \
  man/git-lfs-fetch.1 \
  man/git-lfs-filter-process.1 \
  man/git-lfs-fsck.1 \
  man/git-lfs-install.1 \
  man/git-lfs-lock.1 \
  man/git-lfs-locks.1 \
  man/git-lfs-logs.1 \
  man/git-lfs-ls-files.1 \
  man/git-lfs-migrate.1 \
  man/git-lfs-pointer.1 \
  man/git-lfs-post-checkout.1 \
  man/git-lfs-post-commit.1 \
  man/git-lfs-post-merge.1 \
  man/git-lfs-pre-push.1 \
  man/git-lfs-prune.1 \
  man/git-lfs-pull.1 \
  man/git-lfs-push.1 \
  man/git-lfs-smudge.1 \
  man/git-lfs-status.1 \
  man/git-lfs-track.1 \
  man/git-lfs-uninstall.1 \
  man/git-lfs-unlock.1 \
  man/git-lfs-untrack.1 \
  man/git-lfs-update.1 \
  man/git-lfs.1

# MAN_HTML_TARGETS is a list of all HTML-style targets in the man pages.
MAN_HTML_TARGETS = man/git-lfs-checkout.1.html \
  man/git-lfs-clean.1.html \
  man/git-lfs-clone.1.html \
  man/git-lfs-config.5.html \
  man/git-lfs-env.1.html \
  man/git-lfs-ext.1.html \
  man/git-lfs-fetch.1.html \
  man/git-lfs-filter-process.1.html \
  man/git-lfs-fsck.1.html \
  man/git-lfs-install.1.html \
  man/git-lfs-lock.1.html \
  man/git-lfs-locks.1.html \
  man/git-lfs-logs.1.html \
  man/git-lfs-ls-files.1.html \
  man/git-lfs-migrate.1.html \
  man/git-lfs-pointer.1.html \
  man/git-lfs-post-checkout.1.html \
  man/git-lfs-post-commit.1.html \
  man/git-lfs-post-merge.1.html \
  man/git-lfs-pre-push.1.html \
  man/git-lfs-prune.1.html \
  man/git-lfs-pull.1.html \
  man/git-lfs-push.1.html \
  man/git-lfs-smudge.1.html \
  man/git-lfs-status.1.html \
  man/git-lfs-track.1.html \
  man/git-lfs-uninstall.1.html \
  man/git-lfs-unlock.1.html \
  man/git-lfs-untrack.1.html \
  man/git-lfs-update.1.html \
  man/git-lfs.1.html

# man generates all ROFF- and HTML-style manpage targets.
.PHONY : man
man : $(MAN_ROFF_TARGETS) $(MAN_HTML_TARGETS)

# man/% generates ROFF-style man pages from the corresponding .ronn file.
man/% : docs/man/%.ronn
	@mkdir -p man
	$(RONN) $(RONN_EXTRA_ARGS) -r --pipe < $^ > $@

# man/%.html generates HTML-style man pages from the corresponding .ronn file.
man/%.html : docs/man/%.ronn
	@mkdir -p man
	$(RONN) $(RONN_EXTRA_ARGS) -5 --pipe < $^ > $@
