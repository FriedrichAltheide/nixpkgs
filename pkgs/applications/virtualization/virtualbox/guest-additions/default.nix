{ config, stdenv, fetchurl, lib, pam, libxslt
, libX11, libXext, libXcursor, libXmu, SDL2
, glib, alsa-lib, libXrandr, dbus
, pkg-config, which, substituteAll, gsoap, zlib
, yasm, xorg, kernel, patchelf, makeWrapper, cdrkit, makeself
, linuxPackages, linuxHeaders, openssl, libpulseaudio, virtualbox, pkgs}:

with lib;

let
  buildType = "release";

  # Forced to 1.18; vboxvideo doesn't seem to provide any newer ABI,
  # and nixpkgs doesn't support older ABIs anymore.
  xserverABI = "118";

  # Specifies how to patch binaries to make sure that libraries loaded using
  # dlopen are found. We grep binaries for specific library names and patch
  # RUNPATH in matching binaries to contain the needed library paths.
  dlopenLibs = [
    { name = "libdbus-1.so"; pkg = dbus; }
    { name = "libXfixes.so"; pkg = xorg.libXfixes; }
    { name = "libXrandr.so"; pkg = xorg.libXrandr; }
  ];

  virtualBoxNixGuestAdditionsBuilder = stdenv.mkDerivation (finalAttrs: {
    name = "VirtualBox-GuestAdditions-${version}-${kernel.version}-iso";
    version = "7.0.12";

    src = fetchurl {
      url = "https://download.virtualbox.org/virtualbox/${finalAttrs.version}/VirtualBox-${finalAttrs.version}a.tar.bz2";
      sha256 = "629261a711168c98d95180f14a8e6d814a71e9764f4657c4242e48cb24abb19e";
    };

    env.NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration";

    nativeBuildInputs = [ patchelf makeWrapper pkg-config which yasm ];
    buildInputs =  kernel.moduleBuildDependencies ++ [ libxslt libX11 libXext libXcursor
      glib alsa-lib makeself pam libXmu libXrandr linuxHeaders openssl libpulseaudio ];

    prePatch = virtualbox.prePatch;

    postPatch = ''
      substituteInPlace ./src/VBox/Additions/common/VBoxGuest/lib/VBoxGuestR3LibDrmClient.cpp --replace /usr/bin/VBoxDRMClient /run/current-system/sw/bin/VBoxDRMClient
      substituteInPlace ./src/VBox/Additions/common/VBoxGuest/lib/VBoxGuestR3LibDrmClient.cpp --replace /usr/bin/VBoxClient /run/current-system/sw/bin/VBoxClient
      substituteInPlace ./src/VBox/Additions/x11/VBoxClient/display.cpp --replace /usr/X11/bin/xrandr ${xorg.xrandr}/bin/xrandr
    '';

    configurePhase = ''
        NIX_CFLAGS_COMPILE=$(echo "$NIX_CFLAGS_COMPILE" | sed 's,\-isystem ${lib.getDev stdenv.cc.libc}/include,,g')

        cat >> LocalConfig.kmk <<LOCAL_CONFIG
        VBOX_WITH_TESTCASES            :=
        VBOX_WITH_TESTSUITE            :=
        VBOX_WITH_VALIDATIONKIT        :=
        VBOX_WITH_DOCS                 :=
        VBOX_WITH_WARNINGS_AS_ERRORS   :=

        VBOX_WITH_ORIGIN               :=
        VBOX_PATH_APP_PRIVATE_ARCH_TOP := $out/share/virtualbox
        VBOX_PATH_APP_PRIVATE_ARCH     := $out/libexec/virtualbox
        VBOX_PATH_SHARED_LIBS          := $out/libexec/virtualbox
        VBOX_WITH_RUNPATH              := $out/libexec/virtualbox
        VBOX_PATH_APP_PRIVATE          := $out/share/virtualbox
        VBOX_PATH_APP_DOCS             := $out/doc

        VBOX_ONLY_ADDITIONS := 1
        VBOX_WITH_SHARED_CLIPBOARD := 1
        VBOX_WITH_GUEST_PROPS := 1
        VBOX_WITH_VMSVGA := 1
        VBOX_WITH_SHARED_FOLDERS := 1
        VBOX_WITH_GUEST_CONTROL := 1
        LOCAL_CONFIG

        ./configure \
          --only-additions \
          --with-openssl-dir=${openssl.dev}
      '';

    buildPhase = ''
      runHook preBuild

      source env.sh
      VBOX_ONLY_ADDITIONS=1 VBOX_ONLY_BUILD=1 kmk -j $NIX_BUILD_CORES BUILD_TYPE="${buildType}"
      VBOX_ONLY_ADDITIONS=1 VBOX_ONLY_BUILD=1 kmk packing

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -rv ./out/linux.${if stdenv.hostPlatform.is32bit then "x86" else "amd64"}/${buildType}/bin/additions/VBoxGuestAdditions-${if stdenv.hostPlatform.is32bit then "x86" else "amd64"}.tar.bz2 $out/

      runHook postInstall
    '';
  });

  guestVirtualBoxAdditions = stdenv.mkDerivation (finalAttrs: {
    name = "VirtualBox-GuestAdditions-${virtualBoxNixGuestAdditionsBuilder.version}-${kernel.version}";

    src = "${virtualBoxNixGuestAdditionsBuilder}/VBoxGuestAdditions-${if stdenv.hostPlatform.is32bit then "x86" else "amd64"}.tar.bz2";
    sourceRoot = ".";

    KERN_DIR = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
    KERN_INCL = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";

    hardeningDisable = [ "pic" ];

    env.NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration";

    nativeBuildInputs = [ patchelf makeWrapper ];
    buildInputs = [ virtualBoxNixGuestAdditionsBuilder cdrkit ] ++ kernel.moduleBuildDependencies;

    buildPhase = ''
      runHook preBuild

      # Build kernel modules.
      cd src
      find . -type f | xargs sed 's/depmod -a/true/' -i
      cd vboxguest-${virtualBoxNixGuestAdditionsBuilder.version}
      # Run just make first. If we only did make install, we get symbol warnings during build.
      make -j $NIX_BUILD_CORES
      cd ../..

      # Change the interpreter for various binaries
      for i in sbin/VBoxService bin/{VBoxClient,VBoxControl,VBoxDRMClient} other/mount.vboxsf; do
          patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} $i
          patchelf --set-rpath ${lib.makeLibraryPath [ stdenv.cc.cc stdenv.cc.libc zlib
            xorg.libX11 xorg.libXt xorg.libXext xorg.libXmu xorg.libXfixes xorg.libXcursor ]} $i
      done

      # FIXME: Virtualbox 4.3.22 moved VBoxClient-all (required by Guest Additions
      # NixOS module) to 98vboxadd-xclient. For now, just work around it:
      mv other/98vboxadd-xclient bin/VBoxClient-all

      # Remove references to /usr from various scripts and files
      sed -i -e "s|/usr/bin|$out/bin|" other/vboxclient.desktop
      sed -i -e "s|/usr/bin|$out/bin|" bin/VBoxClient-all

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Install kernel modules.
      cd src/vboxguest-${virtualBoxNixGuestAdditionsBuilder.version}
      make install INSTALL_MOD_PATH=$out KBUILD_EXTRA_SYMBOLS=$PWD/vboxsf/Module.symvers
      cd ../..

      # Install binaries
      install -D -m 755 other/mount.vboxsf $out/bin/mount.vboxsf
      install -D -m 755 sbin/VBoxService $out/bin/VBoxService

      mkdir -p $out/bin
      install -m 755 bin/VBoxClient $out/bin
      install -m 755 bin/VBoxControl $out/bin
      install -m 755 bin/VBoxClient-all $out/bin
      install -m 755 bin/VBoxDRMClient $out/bin

      wrapProgram $out/bin/VBoxClient-all \
              --prefix PATH : "${which}/bin"

      # Don't install VBoxOGL for now
      # It seems to be broken upstream too, and fixing it is far down the priority list:
      # https://www.virtualbox.org/pipermail/vbox-dev/2017-June/014561.html
      # Additionally, 3d support seems to rely on VBoxOGL.so being symlinked from
      # libGL.so (which we can't), and Oracle doesn't plan on supporting libglvnd
      # either. (#18457)

      # Install Xorg drivers
      mkdir -p $out/lib/xorg/modules/{drivers,input}
      install -m 644 other/vboxvideo_drv_${xserverABI}.so $out/lib/xorg/modules/drivers/vboxvideo_drv.so

      runHook postInstall
    '';

    # Stripping breaks these binaries for some reason.
    dontStrip = true;

    # Patch RUNPATH according to dlopenLibs (see the comment there).
    postFixup = lib.concatMapStrings (library: ''
      for i in $(grep -F ${lib.escapeShellArg library.name} -l -r $out/{lib,bin}); do
        origRpath=$(patchelf --print-rpath "$i")
        patchelf --set-rpath "$origRpath:${lib.makeLibraryPath [ library.pkg ]}" "$i"
      done
    '') dlopenLibs;

    meta = {
      description = "Guest additions for VirtualBox";
      longDescription = ''
        Various add-ons which makes NixOS work better as guest OS inside VirtualBox.
        This add-on provides support for dynamic resizing of the X Display, shared
        host/guest clipboard support and guest OpenGL support.
      '';
      sourceProvenance = with lib.sourceTypes; [ fromSource ];
      license = licenses.gpl2;
      maintainers = [ lib.maintainers.sander ];
      platforms = [ "i686-linux" "x86_64-linux" ];
      broken = stdenv.hostPlatform.is32bit && (kernel.kernelAtLeast "5.10");
    };
  });
in guestVirtualBoxAdditions
