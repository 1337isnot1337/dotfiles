set -U fish_user_paths $fish_user_paths $HOME/.local/bin
set fish_greeting
set TERM "xterm-256color"
set EDITOR "vim"
set VISUAL "kate"
set -U fish_color_user brmagenta
set -U fish_color_host purple
set -U fish_color_host_remote purple

hyfetch -b fastfetch
alias pac="pacman -Syu"
alias grep="grep --color=auto"
alias ls="exa"
alias please="sudo"
alias pacman="sudo pacman"
echo ":3"
if status is-interactive
    # Commands to run in interactive sessions can go here
end

starship init fish | source


fish_add_path /home/cinna/.spicetify
