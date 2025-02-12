let { NickelDerivation, Derivation, NixString, .. } = import "contracts.ncl" in

let lib = import "lib.ncl" in

let concat_strings_sep = fun sep values =>
  if std.array.length values == 0 then
    ""
  else
    std.array.reduce_left (fun acc value => nix-s%"%{acc}%{sep}%{value}"%) values
in
{
  NickelPkg
  # we should only need two '%%', but a current Nickel bug (#XXX) bug makes the example being
  # recognized as actual interpolation. For the time being, we thus use a
  # three '%' delimiter.
    | doc m%%%"
      The most basic builder. Simply alias to `NickelDerivation`.

      Example:

      Here is a simple example of a function producing a Nickel derivation
      using the `NickelPkg` builder.

      ```nickel
      output = fun { inputs, nix, .. } =>
      {
        name = "hello",
        version = "0.1",
        build_command = {
          cmd = nix-s%"%{inputs.bash}/bin/bash"%,
          args = [ "-c",
            nix-s%"
              %{inputs.gcc}/bin/gcc %{nix.lib.import_file "hello.c"} -o hello
              %{inputs.coreutils}/bin/mkdir -p $out/bin
              %{inputs.coreutils}/bin/cp hello $out/bin/hello
             "%
          ]
        },
      } | nix.builders.NickelPkg
      ```
      "%%%
    = NickelDerivation,

  NixpkgsPkg
    | doc m%"
      Makes a derivation that runs all the build phases from nixpkgs' stdenv as the `build_command`.
      Can be controlled with environment variables in the same way as `stdenv.mkDerivation`.
    "%
    =
      {
        name,
        version,
        build_command = {
          cmd = nix-s%"%{lib.import_nix "nixpkgs#bash"}/bin/bash"%,
          args = ["-c", "set -euo pipefail; source .attrs.sh; source $stdenv/setup; genericBuild"],
        },
        structured_env = {},
        env = {
          stdenv = lib.import_nix "nixpkgs#stdenv"
        },
        nix_drv = env & structured_env,
      }
        | NickelPkg,

  Shell
    | doc m%"
      A derivation that is to be used as a shell, e.g. with `nix develop`.
      Analogous to `mkShell`.
    "%
    =
      NixpkgsPkg
      & {
        hooks | doc "Bash scripts to run when entering the shell" = {},

        name | default = "shell",
        version | default = "dev",
        packages | doc "Packages to be added to the shell, setting PATH, LD_LIBRARY_PATH and other variables as needed" = {},

        env.buildCommand = nix-s%"
          echo "This derivation is not supposed to be built" 1>&2 1>/dev/null
          exit 1
        "%,
        env.shellHook = concat_strings_sep "\n" (std.record.values hooks),
        structured_env.buildInputs = packages,
      }
        | (NickelPkg & { packages | { _ : Derivation } }),
}
