{
  description = "Logos monerod_ui: run and manage a local Monero node.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # TODO: github:logos-co/logos-monerod-module once that repo is published.
    monerod_module = {
      url = "git+file:///Users/dlipicar/repos/logos-monerod-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
