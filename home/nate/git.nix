{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Nathan Espejo";
        email = "nate.e.espejo@gmail.com";
      };
      alias = {
        co = "checkout";
        br = "branch";
        ci = "commit";
        st = "status";
      };
      init.defaultBranch = "master";
      pull.rebase = true;
      push.autoSetupRemote = true;
      diff = {
        algorithm = "histogram";
        colorMoved = "plain";
        mnemonicPrefix = true;
      };
      commit.verbose = true;
      column.ui = "auto";
      branch.sort = "-committerdate";
      tag.sort = "-version:refname";
      rerere = {
        enabled = true;
        autoupdate = true;
      };
      credential.helper = "cache";
      url = {
        "git@github.com:".insteadOf = "https://github.com/";
      };
      color = {
        ui = "auto";
        status = "always";
      };
    };
    includes = [
      {
        condition = "gitdir:/etc/nixos/";
        contents = {
          user.email = "nate@home.lab";
        };
      }
    ];
  };
}
