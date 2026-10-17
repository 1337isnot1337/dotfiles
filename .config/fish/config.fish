# Keep user-installed tools ahead of system binaries without accumulating
# duplicate entries in fish_user_paths on every shell startup.
fish_add_path --move "$HOME/.local/bin"
fish_add_path --move "$HOME/.spicetify"
fish_add_path --move "$HOME/.pixi/bin"

# Keep the existing editor choices and use a cohesive burgundy/coral/gold theme
# for Fish's command line, autosuggestions, and completion pager.
set --global fish_greeting
set --global EDITOR vim
set --global VISUAL kate
set --global fish_color_normal "#F8E6C4"
set --global fish_color_command "#E3BC84" --bold
set --global fish_color_keyword "#C792EA" --bold
set --global fish_color_quote "#EBCC8C"
set --global fish_color_param "#D9C2E9"
set --global fish_color_option "#F0A6CA"
set --global fish_color_comment "#8F7A89"
set --global fish_color_error "#FF6B6B" --bold
set --global fish_color_autosuggestion "#8F7A89"
set --global fish_color_user "#DB855C"
set --global fish_color_host "#E3BC84"
set --global fish_color_host_remote "#EBCC8C"
set --global fish_color_valid_path "#F8E6C4" --underline
set --global fish_color_selection "#F8E6C4" --bold --background="#3C2638"
set --global fish_pager_color_background "#261923"
set --global fish_pager_color_completion "#F8E6C4"
set --global fish_pager_color_description "#B8A0AF"
set --global fish_pager_color_prefix "#DB855C" --bold --underline
set --global fish_pager_color_selected_background "#68334C"
set --global fish_pager_color_selected_completion "#F8E6C4" --bold
set --global fish_pager_color_selected_description "#EBCC8C"
set --global fish_pager_color_progress "#F8E6C4" --background="#B85D60"

# Share the same palette with file listings, syntax previews, and Exa's
# predecessor. These are true-color values, so they stay close to Starship.
set --global --export EZA_COLORS "di=38;2;235;204;140:ex=38;2;219;133;92:ln=38;2;199;146;234:or=38;2;255;107;107:fi=38;2;248;230;196:uu=38;2;219;133;92:gu=38;2;184;93;96:da=38;2;143;122;137:hd=1;38;2;248;230;196:xx=38;2;143;122;137:ga=38;2;120;206;170:gm=38;2;219;133;92:gd=38;2;255;107;107:gv=38;2;199;146;234:gi=38;2;143;122;137:gc=1;38;2;255;107;107:im=38;2;199;146;234:vi=38;2;199;146;234:mu=38;2;227;188;132:lo=38;2;227;188;132:cr=38;2;255;107;107:do=38;2;235;204;140:co=38;2;184;93;96:tm=2;38;2;143;122;137:cm=38;2;227;188;132:bu=1;38;2;235;204;140:sc=38;2;227;188;132"
set --global --export EXA_COLORS "$EZA_COLORS"
set --global --export BAT_THEME "Sublime Snazzy"

# Shortcuts already used in this shell.
alias hyfetch="hyfetch -b fastfetch"
alias pac="pacman -Syu"
alias pget="wget -c --timeout=30 --tries=0 --retry-connrefused --read-timeout=60 --waitretry=30"
alias grep="grep --color=auto"
alias please="sudo"
alias pacman="sudo pacman"
alias cp="cp -r"
alias rm="rm -r"
alias ip="ip -c"

# In Kitty, pass SSH sessions through its kitten so remote hosts receive
# Kitty's terminfo and shell integration automatically.
if status is-interactive; and set -q KITTY_WINDOW_ID; and command -q kitten
    function ssh --wraps ssh --description 'SSH with Kitty terminal support'
        command kitten ssh $argv
    end
end

# Optional modern replacements: fall back to the normal commands if these
# programs are not installed.
if command -q eza
    alias ls="eza -lah --icons=auto --git --group-directories-first"
    alias ll="eza -lh --icons=auto --git --group-directories-first"
    alias la="eza -la --icons=auto --git --group-directories-first"
end

if command -q bat
    alias cat="bat -p --paging=never"
end

# Small Git shortcuts, available only when Git is installed.
if command -q git
    alias g="git"
    alias gs="git status"
    alias gd="git diff"
end
