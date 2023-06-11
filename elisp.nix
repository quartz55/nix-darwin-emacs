/*
  Parse an emacs lisp configuration file to derive packages from
  use-package declarations.
*/

{ pkgs }:
let
  parse = pkgs.callPackage ./parse.nix { };
  inherit (pkgs) lib;
in
{ config
  # bool to use the value of config or a derivation whose name is default.el
, defaultInitFile ? false
  # emulate `#+PROPERTY: header-args:emacs-lisp :tangle yes`
, alwaysTangle ? false
, extraEmacsPackages ? epkgs: [ ]
, package ? pkgs.emacs-darwin
, override ? (self: super: { })
}:
let
  configType = config:
    if (lib.strings.isStorePath config) then "path"
    else (builtins.typeOf config);

  isOrgModeFile =
    let
      ext = lib.last (builtins.split "\\." (builtins.toString config));
      type = configType config;
    in
    type == "path" && ext == "org";

  configText =
    let
      type = configType config;
    in
    if type == "string" then config
    else if type == "path" then builtins.readFile config
    else throw "Unsupported type for config: \"${type}\"";

  packages = parse.parsePackagesFromUsePackage {
    inherit configText isOrgModeFile alwaysTangle;
    alwaysEnsure = false;
  };
  emacsPackages = (pkgs.emacsPackagesFor package).overrideScope' (self: super:
    # for backward compatibility: override was a function with one parameter
    if builtins.isFunction (override super)
    then override self super
    else override super
  );
  emacsWithPackages = emacsPackages.emacsWithPackages;
  mkPackageError = name:
    throw "Emacs package ${name}, declared wanted with use-package, not found." null;
in
emacsWithPackages (epkgs:
let
  usePkgs = map (name: epkgs.${name} or (mkPackageError name)) packages;
  extraPkgs = extraEmacsPackages epkgs;
  defaultInitFilePkg =
    if !((builtins.isBool defaultInitFile) || (lib.isDerivation defaultInitFile))
    then throw "defaultInitFile must be bool or derivation"
    else
      if defaultInitFile == false
      then null
      else
        let
          # name of the default init file must be default.el according to elisp manual
          defaultInitFileName = "default.el";
        in
        epkgs.trivialBuild {
          pname = "default-init-file";
          src =
            if defaultInitFile == true
            then pkgs.writeText defaultInitFileName configText
            else
              if defaultInitFile.name == defaultInitFileName
              then defaultInitFile
              else throw "name of defaultInitFile must be ${defaultInitFileName}";
          packageRequires = usePkgs;
        };
in
usePkgs ++ extraPkgs ++ [ defaultInitFilePkg ])
