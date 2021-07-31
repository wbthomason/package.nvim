FROM archlinux:base-devel
SHELL ["/bin/bash", "-c"]
WORKDIR setup
RUN pacman -Sy
RUN pacman -S git --noconfirm
RUN git clone --depth 1 https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim
RUN ln -s $(pwd) ~/.local/share/nvim/site/pack/vendor/start
RUN curl -OL https://raw.githubusercontent.com/norcalli/bot-ci/master/scripts/github-actions-setup.sh
RUN source github-actions-setup.sh nightly_x64
#RUN mkdir ~/.cache/nvim/packer
WORKDIR /app
ENTRYPOINT /setup/_neovim/bin/nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal.vim'}"
