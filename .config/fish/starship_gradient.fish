# Starship owns the prompt content; this renderer replaces its block colors
# with one continuous true-color background gradient across every terminal
# column. Keep this file sourced after `starship init fish`.

function __starship_render_gradient --description 'Render Starship as a continuous true-color gradient'
    set -l raw (string join '' -- $argv)

    # Keep Starship's dynamic text, but discard its ANSI styling and the old
    # powerline boundaries before painting the final prompt.
    set -l plain (string replace -ra '\x1b\[[0-9;?]*[ -/]*[@-~]' '' -- "$raw")
    set plain (string replace -a '' '' -- "$plain")
    set plain (string replace -a '' '' -- "$plain")
    set plain (string replace -a '' '' -- "$plain")
    set plain (string replace -ra '[[:space:]]+' ' ' -- "$plain")
    set plain (string trim -- "$plain")

    if test -z "$plain"
        printf '\e[1;38;2;248;230;196m❯\e[0m '
        return
    end

    # Deep plum (#3B2638) to warm rose (#A46352). The interpolation happens
    # once per visible column, rather than once per Starship module.
    set -l start_r 59
    set -l start_g 38
    set -l start_b 56
    set -l end_r 164
    set -l end_g 99
    set -l end_b 82
    set -l text_r 255
    set -l text_g 240
    set -l text_b 208

    set -l width (string length --visible "$plain")
    set -l denominator (math "$width - 1")
    if test $denominator -lt 1
        set denominator 1
    end

    printf '\e[0m\e[38;2;%d;%d;%dm' $start_r $start_g $start_b

    set -l column 0
    for char in (string split '' -- "$plain")
        set -l red (math "round($start_r + ($end_r - $start_r) * $column / $denominator)")
        set -l green (math "round($start_g + ($end_g - $start_g) * $column / $denominator)")
        set -l blue (math "round($start_b + ($end_b - $start_b) * $column / $denominator)")

        printf '\e[1;38;2;%d;%d;%d;48;2;%d;%d;%dm%s' \
            $text_r $text_g $text_b $red $green $blue "$char"

        set -l char_width (string length --visible "$char")
        if test $char_width -lt 1
            set char_width 1
        end
        set column (math "$column + $char_width")
    end

    printf '\e[0m\e[38;2;%d;%d;%dm\e[0m ' $end_r $end_g $end_b
end

# This mirrors Starship's generated Fish prompt function so command status,
# pipeline status, duration, jobs, vi mode, and transient prompts still work.
function fish_prompt
    switch "$fish_key_bindings"
        case fish_hybrid_key_bindings fish_vi_key_bindings fish_helix_key_bindings
            set STARSHIP_KEYMAP "$fish_bind_mode"
        case '*'
            set STARSHIP_KEYMAP insert
    end

    set STARSHIP_CMD_PIPESTATUS $pipestatus
    set STARSHIP_CMD_STATUS $status
    set STARSHIP_DURATION "$CMD_DURATION$cmd_duration"

    __starship_set_job_count

    if contains -- --final-rendering $argv; or test "$TRANSIENT" = 1
        if test "$TRANSIENT" = 1
            set -g TRANSIENT 0
            printf '\e[0J'
        end
        if type -q starship_transient_prompt_func
            starship_transient_prompt_func --terminal-width="$COLUMNS" --status=$STARSHIP_CMD_STATUS --pipestatus="$STARSHIP_CMD_PIPESTATUS" --keymap=$STARSHIP_KEYMAP --cmd-duration=$STARSHIP_DURATION --jobs=$STARSHIP_JOBS
        else
            printf '\e[1;32m❯\e[0m '
        end
    else
        set -l starship_output (/usr/bin/starship prompt --terminal-width="$COLUMNS" --status=$STARSHIP_CMD_STATUS --pipestatus="$STARSHIP_CMD_PIPESTATUS" --keymap=$STARSHIP_KEYMAP --cmd-duration=$STARSHIP_DURATION --jobs=$STARSHIP_JOBS | string collect)
        __starship_render_gradient "$starship_output"
    end
end
