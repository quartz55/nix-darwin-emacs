self: super:
let
  mkGitEmacs = namePrefix: jsonFile: { ... }@args:
    let
      repoMeta = super.lib.importJSON jsonFile;
      fetcher =
        if repoMeta.type == "savannah" then
          super.fetchFromSavannah
        else if repoMeta.type == "github" then
          super.fetchFromGitHub
        else
          throw "Unknown repository type ${repoMeta.type}!";
    in
    builtins.foldl'
      (drv: fn: fn drv)
      super.emacs
      ([

        (drv: drv.override ({ srcRepo = true; } // args))

        (
          drv: drv.overrideAttrs (
            old: {
              name = "${namePrefix}-${repoMeta.version}";
              inherit (repoMeta) version;
              src = fetcher (builtins.removeAttrs repoMeta [ "type" "version" ]);

              patches = [
                ./patches/no-frame-refocus-cocoa.patch

                # GNU Emacs's main role is an AXTextField instead of AXWindow, it has to be fixed manually.
                # The patches is borrowed from https://github.com/d12frosted/homebrew-emacs-plus/blob/f3c16d68bbf52c1779be279579d124d726f0d04a/patches/emacs-28/
                ./patches/fix-window-role.patch

                ./patches/system-appearance.patch
                ./patches/poll.patch
                ./patches/round-undecorated-frame.patch
              ];

              postInstall = old.postInstall + ''
                cp ${./icons/memeplex-wide.icns} $out/Applications/Emacs.app/Contents/Resources/Emacs.icns
              '';

              postPatch = old.postPatch + ''
                substituteInPlace lisp/loadup.el \
                --replace '(emacs-repository-get-version)' '"${repoMeta.rev}"' \
                --replace '(emacs-repository-get-branch)' '"master"'
              '' +
                # XXX: remove when https://github.com/NixOS/nixpkgs/pull/193621 is merged
                (super.lib.optionalString (old ? NATIVE_FULL_AOT)
                  (
                    let
                      backendPath = (super.lib.concatStringsSep " "
                        (builtins.map (x: ''\"-B${x}\"'') [
                          # Paths necessary so the JIT compiler finds its libraries:
                          "${super.lib.getLib self.libgccjit}/lib"
                          "${super.lib.getLib self.libgccjit}/lib/gcc"
                          "${super.lib.getLib self.stdenv.cc.libc}/lib"

                          # Executable paths necessary for compilation (ld, as):
                          "${super.lib.getBin self.stdenv.cc.cc}/bin"
                          "${super.lib.getBin self.stdenv.cc.bintools}/bin"
                          "${super.lib.getBin self.stdenv.cc.bintools.bintools}/bin"
                        ]));
                    in
                    ''
                                              substituteInPlace lisp/emacs-lisp/comp.el --replace \
                                                  "(defcustom comp-libgccjit-reproducer nil" \
                                                  "(setq native-comp-driver-options '(${backendPath}))
                      (defcustom comp-libgccjit-reproducer nil"
                    ''
                  ));
            }
          )
        )

        # reconnect pkgs to the built emacs
        (
          drv:
          let
            result = drv.overrideAttrs (old: {
              passthru = old.passthru // {
                pkgs = self.emacsPackagesFor result;
              };
            });
          in
          result
        )

        (
          drv: drv.overrideAttrs (old:
            let
              libName = drv: super.lib.removeSuffix "-grammar" drv.pname;
              lib = drv: ''lib${libName drv}.dylib'';
              linkCmd = drv: ''
                cp ${drv}/parser .
                chmod +w ./parser
                install_name_tool -id $out/lib/${lib drv} ./parser
                cp ./parser $out/lib/${lib drv}
                /usr/bin/codesign -s - -f $out/lib/${lib drv}
              '';
              linkerFlag = drv: "-l" + libName drv;
              plugins = with self.pkgs.tree-sitter-grammars; [
                tree-sitter-bash
                tree-sitter-c
                tree-sitter-c-sharp
                tree-sitter-cmake
                tree-sitter-cpp
                tree-sitter-css
                tree-sitter-dockerfile
                tree-sitter-go
                tree-sitter-gomod
                tree-sitter-java
                tree-sitter-python
                tree-sitter-javascript
                tree-sitter-json
                tree-sitter-rust
                tree-sitter-toml
                tree-sitter-tsx
                tree-sitter-typescript
                tree-sitter-yaml
                tree-sitter-elixir
                tree-sitter-heex
                tree-sitter-eex
              ];
              tree-sitter-grammars = super.runCommandCC "tree-sitter-grammars" { }
                (super.lib.concatStringsSep "\n" ([ "mkdir -p $out/lib" ] ++ (map linkCmd plugins)));
            in
            {
              buildInputs = old.buildInputs ++ [ self.pkgs.tree-sitter tree-sitter-grammars ];

              # before building the `.el` files, we need to allow the `tree-sitter` libraries
              # bundled in emacs to be dynamically loaded.
              TREE_SITTER_LIBS = super.lib.concatStringsSep " " ([ "-ltree-sitter" ] ++ (map linkerFlag plugins));

              # Add to directories that tree-sitter looks in for language definitions / shared object parsers
              # https://git.savannah.gnu.org/cgit/emacs.git/tree/src/treesit.c?h=64044f545add60e045ff16a9891b06f429ac935f#n533
              # appends a bunch of filenames that appear to be incorrectly skipped over
              # in https://git.savannah.gnu.org/cgit/emacs.git/tree/src/treesit.c?h=64044f545add60e045ff16a9891b06f429ac935f#n567
              # on macOS
              postPatch = old.postPatch + ''
                substituteInPlace src/treesit.c \
                --replace "Vtreesit_extra_load_path = Qnil;" \
                          "Vtreesit_extra_load_path = list1 ( build_string ( \"${tree-sitter-grammars}/lib\" ) );"
              '';
            }
          )
        )
      ]);
in
{
  emacsGit = mkGitEmacs "emacs-git" ../repos/emacs/emacs-master.json {
    withSQLite3 = true;
    withWebP = true;
  };

  emacsWithPackagesFromUsePackage = import ../elisp.nix { pkgs = self; };

  emacsWithPackagesFromPackageRequires = import ../packreq.nix { pkgs = self; };

}
