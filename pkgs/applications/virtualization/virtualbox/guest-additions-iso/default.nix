{ stdenv, fetchurl, lib, virtualbox}:

let
  inherit (virtualbox) version;
in
stdenv.mkDerivation rec {
  pname = "VirtualBox-GuestAdditions-iso";
  inherit version;

  src = fetchurl {
    url = "http://download.virtualbox.org/virtualbox/${version}/VBoxGuestAdditions_${version}.iso";
    sha256 = "b37f6aabe5a32e8b96ccca01f37fb49f4fd06674f1b29bc8fe0f423ead37b917";
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    cp $src $out/
  '';

  meta = {
    description = "Guest additions ISO for VirtualBox";
    longDescription = ''
      ISO containing various add-ons which improves guests inside VirtualBox.
    '';
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.gpl2;
    maintainers = [ lib.maintainers.sander ];
    platforms = [ "i686-linux" "x86_64-linux" ];
  };
}
