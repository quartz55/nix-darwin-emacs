self: super:

{
  emacsPackagesFor = emacs: (
    (super.emacsPackagesFor emacs).overrideScope' (
      eself: esuper:
        let
          melpaStablePackages = esuper.melpaStablePackages.override {
            archiveJson = ../repos/melpa/recipes-archive-melpa.json;
          };

          melpaPackages = esuper.melpaPackages.override {
            archiveJson = ../repos/melpa/recipes-archive-melpa.json;
          };

          elpaPackages = esuper.elpaPackages.override {
            generated = ../repos/elpa/elpa-generated.nix;
          };

          epkgs = esuper.override {
            inherit melpaStablePackages melpaPackages elpaPackages;
          };

        in
        epkgs
        // super.lib.optionalAttrs (super.lib.hasAttr "nongnuPackages" esuper) {
          nongnuPackages = esuper.nongnuPackages.override {
            generated = ../repos/nongnu/nongnu-generated.nix;
          };
        }
    )
  );

}
