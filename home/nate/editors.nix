{ ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = true;
    withPython3 = true;
  };

  home.file.".config/nvim" = {
    source = ./nvim;
    recursive = true;
  };
}
