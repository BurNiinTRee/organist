let inputs = import "./nickel.lock.ncl" in
let organist = inputs.organist in

{
  shells = organist.shells.Bash,

  shells.build = {
    packages = {},
  },

  shells.dev = {
    packages.hello = organist.lib.import_nix "nixpkgs#hello",
  },
}
  | organist.contracts.OrganistExpression
