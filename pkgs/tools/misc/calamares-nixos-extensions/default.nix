{
  stdenv,
  fetchFromGitHub,
  lib,
  writeText,
  nixfmt-rfc-style,
  calamares-nixos,
  snippets ? { },
}:
let
  calamaresSnippetHelper =
    type: subDir: name: filenameFunction: value:
    (
      let
        outPath = "$out/lib/calamares/modules/nixos/customConfigs/${type}/${subDir}/${filenameFunction name}";
        snippetStorePath = writeText name value;
      in
      lib.optionalString (
        lib.typeOf value == "string" && value != ""
      ) "cp ${snippetStorePath} ${lib.strings.normalizePath outPath}\n"
    );
  calamaresSnippetHelperWriteAttrSet =
    type: subDir: filenameFunction: attrSet:
    (lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value: (calamaresSnippetHelper type subDir name filenameFunction value)
      ) attrSet
    ));
  nameToSnippetName = name: ("${name}.snippet");
  nameToName = name: name;
  calamaresSnippetHelperWriteAttrSetSnippets =
    type: subDir: attrSet:
    (calamaresSnippetHelperWriteAttrSet type subDir nameToSnippetName attrSet);
  calamaresSnippetHelperWriteAttrSetModules =
    type: subDir: attrSet:
    (calamaresSnippetHelperWriteAttrSet type subDir nameToName attrSet);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "calamares-nixos-extensions";
  version = "0.3.18";

  src = fetchFromGitHub {
    owner = "NixOS";
    repo = "calamares-nixos-extensions";
    rev = finalAttrs.version;
    hash = "sha256-j+9iZtw9QIKHLo5sr9nkCVoZS7QQCnDDyTGFXD+R+WU=";
  };

  propagatedBuildInputs = [
    nixfmt-rfc-style
  ];

  installPhase =
    ''
      runHook preInstall
      mkdir -p $out/{lib,share}/calamares
      cp -r modules $out/lib/calamares/
      cp -r config/* $out/share/calamares/
      cp -r branding $out/share/calamares/
      mkdir -p $out/lib/calamares/modules/nixos/customConfigs/snippets/desktopEnv
      mkdir -p $out/lib/calamares/modules/nixos/customConfigs/snippets/desktopEnv
      mkdir $out/lib/calamares/modules/nixos/customConfigs/modules
    ''
    + calamaresSnippetHelperWriteAttrSetSnippets "snippets" "" (
      lib.removeAttrs snippets [
        "desktopEnv"
        "modules"
      ]
    )
    + calamaresSnippetHelperWriteAttrSetSnippets "snippets" "desktopEnv" (
      lib.optionalAttrs (builtins.hasAttr "desktopEnv" snippets) snippets.desktopEnv
    )
    + calamaresSnippetHelperWriteAttrSetModules "modules" "" (
      lib.optionalAttrs (builtins.hasAttr "modules" snippets) snippets.modules
    )
    + ''
      runHook postInstall
    '';

  meta = with lib; {
    description = "Calamares modules for NixOS";
    homepage = "https://github.com/NixOS/calamares-nixos-extensions";
    license = with licenses; [
      gpl3Plus
      bsd2
      cc-by-40
      cc-by-sa-40
      cc0
    ];
    maintainers = with maintainers; [ vlinkz ];
    platforms = platforms.linux;
  };
})
