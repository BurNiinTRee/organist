{
  runCommand,
  writeText,
  nickel,
  system,
  lib,
  flakeRoot,
  organistLib,
}: let
  # Export a Nix value to be consumed by Nickel
  typeField = "$__organist_type";

  isInStore = lib.hasPrefix builtins.storeDir;

  # Take a symbolic derivation (a datastructure representing a derivation), as
  # produced by Nickel, and transform it into valid arguments to
  # `derivation`
  prepareDerivation = system: value:
    value
    // {
      system =
        if value.system != null
        then value.system
        else system;
    };

  # Import a Nickel value produced by the Organist DSL
  importFromNickel = flakeInputs: system: baseDir: value: let
    type = builtins.typeOf value;
    isNickelDerivation = type: type == "nickelDerivation";
    importFromNickel_ = importFromNickel flakeInputs system baseDir;
  in
    if (type == "set")
    then
      (
        let
          organistType = value."${typeField}" or "";
        in
          if isNickelDerivation organistType
          then let
            prepared = prepareDerivation system (builtins.mapAttrs (_:
              importFromNickel_)
            value.nix_drv);
          in
            derivation prepared
          else if organistType == "nixString"
          then builtins.concatStringsSep "" (builtins.map importFromNickel_ value.fragments)
          else if organistType == "nixPath"
          then baseDir + "/${value.path}"
          else if organistType == "nixInput"
          then let
            attr_path = value.attr_path;
            possibleAttrPaths = [
              ([value.input] ++ attr_path)
              ([value.input "packages" system] ++ attr_path)
              ([value.input "legacyPackages" system] ++ attr_path)
            ];
            notFound = throw "Missing input \"${value.input}.${lib.strings.concatStringsSep "." attr_path}\"";
            chosenAttrPath =
              lib.findFirst
              (path: lib.hasAttrByPath path flakeInputs)
              notFound
              possibleAttrPaths;
          in
            lib.getAttrFromPath chosenAttrPath flakeInputs
          else builtins.mapAttrs (_: importFromNickel_) value
      )
    else if (type == "list")
    then builtins.map importFromNickel_ value
    else value;

  # Call Nickel on a given Nickel expression with the inputs declared in it.
  # See importNcl for details about the flakeInputs parameter.
  callNickel = {
    nickelFile,
    flakeInputs,
    baseDir,
    lockFileContents,
  }: let
    sources = builtins.path {
      path = baseDir;
      # TODO: filter .ncl files
      # filter =
    };

    lockfilePath = "${sources}/nickel.lock.ncl";
    expectedLockfileContents = organistLib.buildLockFileContents lockFileContents;
    needNewLockfile = !builtins.pathExists lockfilePath || (builtins.readFile lockfilePath) != expectedLockfileContents;

    nickelWithImports = src: ''
      let params = {
        system = "${system}",
      }
      in
      let nix = import "${flakeRoot}/lib/nix.ncl" in

      let nickel_expr | nix.contracts.OrganistExpression =
        import "${src}/${nickelFile}" in

      nickel_expr & params
    '';
  in
    runCommand "nickel-res.json" {
      ___ = flakeRoot; # Make it available in the sandbox as the lockfile relies on it
    } (
      if needNewLockfile
      then
        lib.warn ''
          Lockfile contents are outdated. Please run "nix run .#regenerate-lockfile" to update them.
        ''
        ''
          cp -r "${sources}" sources
          chmod +w sources sources/nickel.lock.ncl
          cat > sources/nickel.lock.ncl <<EOF
          ${expectedLockfileContents}
          EOF
          cat > eval.ncl <<EOF
          ${nickelWithImports "sources"}
          EOF
          ${nickel}/bin/nickel -f eval.ncl export > $out
        ''
      else ''
        cat > eval.ncl <<EOF
        ${nickelWithImports sources}
        EOF
        ${nickel}/bin/nickel -f eval.ncl export > $out
      ''
    );

  # Import a Nickel expression as a Nix value. flakeInputs are where the packages
  # passed to the Nickel expression are taken from. If the Nickel expression
  # declares an input hello from input "nixpkgs", then flakeInputs must have an
  # attribute "nixpkgs" with a package "hello".
  importNcl = baseDir: nickelFile: flakeInputs: lockFileContents: let
    nickelResult = callNickel {
      inherit nickelFile baseDir flakeInputs lockFileContents;
    };
  in
    {rawNickel = nickelResult;}
    // (importFromNickel flakeInputs system baseDir (builtins.fromJSON
        (builtins.unsafeDiscardStringContext (builtins.readFile nickelResult))));
in {inherit importNcl;}
