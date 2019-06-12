BINARY:=unifi-poller
URL=https://github.com/davidnewhall/unifi-poller
MAINT="David Newhall II <david at sleepers dot pro>"
DESC="This daemon polls a Unifi controller at a short interval and stores the collected metric data in an Influx Database."
PACKAGE:=./cmd/$(BINARY)
VERSION:=$(shell git tag -l --merged | tail -n1 | tr -d v)
ITERATION:=$(shell git rev-list --count HEAD)

all: man build

# Prepare a release. Called in Travis CI.
release: clean test $(BINARY)-$(VERSION)-$(ITERATION).x86_64.rpm $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb $(BINARY)-$(VERSION).pkg
	# Prepareing a release!
	mkdir -p release
	gzip -9 $(BINARY).linux
	gzip -9 $(BINARY).macos
	mv $(BINARY)-$(VERSION)-$(ITERATION).x86_64.rpm $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb \
		$(BINARY)-$(VERSION).pkg $(BINARY).macos.gz $(BINARY).linux.gz release/
	# Generating File Hashes
	openssl dgst -sha256 release/* | tee release/$(BINARY)_checksums_$(VERSION)-$(ITERATION).txt

# Delete all build assets.
clean:
	# Cleaning up.
	rm -f $(BINARY){.macos,.linux,.1,}{,.gz}
	rm -f $(BINARY){_,-}*.{deb,rpm,pkg} md2roff
	rm -rf package_build_* release cmd/unifi-poller/README{,.html}

# md2roff is needed to build the man file and html pages from the READMEs.
md2roff:
	go build -o ./md2roff github.com/github/hub/md2roff-bin

# Build a man page from a markdown file using md2roff.
# This also turns the repo readme into an html file.
man: $(BINARY).1.gz
$(BINARY).1.gz: md2roff
	# Building man page. Build dependency first: md2roff
	./md2roff --manual $(BINARY) --version $(VERSION) --date "$$(date)" cmd/unifi-poller/README.md
	gzip -9nc cmd/$(BINARY)/README > $(BINARY).1.gz
	mv cmd/$(BINARY)/README.html ./$(BINARY)_manual.html

# TODO: provide a template that adds the date to the built html file.
readme: README.html
README.html: md2roff
	# This turns README.md into README.html
	./md2roff --manual $(BINARY) --version $(VERSION) --date "$$(date)" README.md
	@rm -f README	# Delete useless "man" formatted version.

# Binaries

build: $(BINARY)
$(BINARY):
	go build -o $(BINARY) -ldflags "-w -s -X main.Version=$(VERSION)" $(PACKAGE)

linux: $(BINARY).linux
$(BINARY).linux:
	# Building linux binary.
	GOOS=linux go build -o $(BINARY).linux -ldflags "-w -s -X main.Version=$(VERSION)" $(PACKAGE)

macos: $(BINARY).macos
$(BINARY).macos:
	# Building darwin binary.
	GOOS=darwin go build -o $(BINARY).macos -ldflags "-w -s -X main.Version=$(VERSION)" $(PACKAGE)

# Packages

rpm: clean $(BINARY)-$(VERSION)-$(ITERATION).x86_64.rpm
$(BINARY)-$(VERSION)-$(ITERATION).x86_64.rpm: check_fpm package_build_linux
	@echo "Building 'rpm' package for $(BINARY) version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t rpm \
		--name $(BINARY) \
		--rpm-os linux \
		--version $(VERSION) \
		--iteration $(ITERATION) \
		--after-install scripts/after-install.sh \
		--before-remove scripts/before-remove.sh \
		--license MIT \
		--url $(URL) \
		--maintainer $(MAINT) \
		--description $(DESC) \
		--chdir package_build_linux

deb: clean $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb
$(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb: check_fpm package_build_linux
	@echo "Building 'deb' package for $(BINARY) version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb \
		--name $(BINARY) \
		--version $(VERSION) \
		--iteration $(ITERATION) \
		--after-install scripts/after-install.sh \
		--before-remove scripts/before-remove.sh \
		--license MIT \
		--url $(URL) \
		--maintainer $(MAINT) \
		--description $(DESC) \
		--chdir package_build_linux

osxpkg: clean $(BINARY)-$(VERSION).pkg
$(BINARY)-$(VERSION).pkg: check_fpm package_build_osx
	@echo "Building 'osx' package for $(BINARY) version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t osxpkg \
		--name $(BINARY) \
		--version $(VERSION) \
		--iteration $(ITERATION) \
		--after-install scripts/after-install.sh \
		--osxpkg-identifier-prefix com.github.davidnewhall \
		--license MIT \
		--url $(URL) \
		--maintainer $(MAINT) \
		--description $(DESC) \
		--chdir package_build_osx

# OSX packages use /usr/local because Apple doesn't allow writing many other places.
package_build_osx: readme man macos
	# Building package environment for macOS.
	mkdir -p $@/usr/local/bin $@/usr/local/etc/$(BINARY) $@/Library/LaunchAgents
	mkdir -p $@/usr/local/share/man/man1 $@/usr/local/share/doc/$(BINARY)/examples $@/usr/local/var/log/unifi-poller
	# Copying the binary, config file and man page into the env.
	cp $(BINARY).macos $@/usr/local/bin/$(BINARY)
	cp *.1.gz $@/usr/local/share/man/man1
	cp examples/*.conf.example $@/usr/local/etc/$(BINARY)/
	cp *.html examples/{*dash.json,up.conf.example} $@/usr/local/share/doc/$(BINARY)/
	# These go to their own folder so the img src in the html pages continue to work.
	cp examples/*.png $@/usr/local/share/doc/$(BINARY)/examples
	cp init/launchd/com.github.davidnewhall.$(BINARY).plist $@/Library/LaunchAgents/

# Build an environment that can be packaged for linux.
package_build_linux: readme man linux
	# Building package environment for linux.
	mkdir -p $@/usr/bin $@/etc/$(BINARY) $@/lib/systemd/system
	mkdir -p $@/usr/share/man/man1 $@/usr/share/doc/$(BINARY)/examples
	# Copying the binary, config file, unit file, and man page into the env.
	cp $(BINARY).linux $@/usr/bin/$(BINARY)
	cp *.1.gz $@/usr/share/man/man1
	cp examples/*.conf.example $@/etc/$(BINARY)/
	cp examples/up.conf.example $@/etc/$(BINARY)/up.conf
	cp *.html examples/{*dash.json,up.conf.example} $@/usr/share/doc/$(BINARY)/
	# These go to their own folder so the img src in the html pages continue to work.
	cp examples/*.png $@/usr/share/doc/$(BINARY)/examples
	cp init/systemd/$(BINARY).service $@/lib/systemd/system/

check_fpm:
	@fpm --version > /dev/null || (echo "FPM missing. Install FPM: https://fpm.readthedocs.io/en/latest/installing.html" && false)

# Extras

# Run code tests and lint.
test: lint
	# Testing.
	go test -race -covermode=atomic $(PACKAGE)
lint:
	# Checking lint.
	golangci-lint run --enable-all -D gochecknoglobals

# Deprecated.
install:
	@echo -  Local installation with the Makefile is no longer possible.
	@echo If you wish to install the application manually, check out the wiki: \
	https://github.com/davidnewhall/unifi-poller/wiki/Installation
	@echo -  Otherwise, build and install a package: make rpm, make deb, make osxpkg
	@echo See the Package Install wiki for more info: \
	https://github.com/davidnewhall/unifi-poller/wiki/Package-Install

# If you installed with `make install` run `make uninstall` before installing a binary package.
# This will remove the package install from macOS, it will not remove a package install from Linux.
uninstall:
	@echo "  ==> You must run make uninstall as root on Linux. Recommend not running as root on macOS."
	[ -x /bin/systemctl ] && /bin/systemctl disable $(BINARY) || true
	[ -x /bin/systemctl ] && /bin/systemctl stop $(BINARY) || true
	[ -x /bin/launchctl ] && [ -f ~/Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist ] \
		&& /bin/launchctl unload ~/Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist || true
	[ -x /bin/launchctl ] && [ -f /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist ] \
		&& /bin/launchctl unload /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist || true
	rm -rf /usr/local/{etc,bin,share/doc}/$(BINARY)
	rm -f ~/Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist
	rm -f /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist || true
	rm -f /etc/systemd/system/$(BINARY).service /usr/local/share/man/man1/$(BINARY).1.gz
	[ -x /bin/systemctl ] && /bin/systemctl --system daemon-reload || true
	@[ -f /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist ] && echo "  ==> Unload and delete this file manually:" && echo "  sudo launchctl unload /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist" && echo "  sudo rm -f /Library/LaunchAgents/com.github.davidnewhall.$(BINARY).plist" || true

# Don't run this unless you're ready to debug untested vendored dependencies.
deps:
	dep ensure -update
