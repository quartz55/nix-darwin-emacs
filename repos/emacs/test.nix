{ pkgs ? import <nixpkgs> { overlays = [ (import ../../default.nix) ]; } }:

let
  mkTestBuild = package:
    let
      emacsPackages = pkgs.emacsPackagesFor package;
      emacsWithPackages = emacsPackages.emacsWithPackages;
    in
    emacsWithPackages (epkgs: [ ]);

in
{
  emacsGit = mkTestBuild pkgs.emacsGit;
}
