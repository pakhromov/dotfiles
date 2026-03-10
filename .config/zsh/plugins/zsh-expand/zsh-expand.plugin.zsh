#!/usr/bin/env zsh
#{{{                    MARK:Header
#**************************************************************
##### Author: MenkeTechnologies
##### GitHub: https://github.com/MenkeTechnologies
##### Date: Tue Aug 11 13:59:02 EDT 2020
##### Purpose: zsh script to parse words and expand aliases
##### Notes:
#}}}***********************************************************

#{{{                    MARK:Global variables
#**************************************************************
#
# According to the standard:
# http://zdharma.org/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

if ! (( $+ZPWR_VARS )) || [[ ${parameters[ZPWR_VARS]} != association ]]; then
    # global map to containerize global variables
    typeset -gA ZPWR_VARS
fi

ZPWR_VARS[ENTER_KEY]='ENTER'
ZPWR_VARS[SPACEBAR_KEY]='SPACE'

if ! (( $+ZPWR_TABSTOP )) || [[ ${parameters[ZPWR_TABSTOP]} != scalar-export ]]; ; then
    export ZPWR_TABSTOP=__________
fi

autoload regexp-replace
setopt extendedglob
setopt rcquotes

ZPWR_VARS[EXPAND_API]=${0:A:h}/zpwrExpandApi.zsh
ZPWR_VARS[EXPAND_LIB]=${0:A:h}/zpwrExpandLib.zsh

if ! source $ZPWR_VARS[EXPAND_API];then
    echo "failed source ZPWR_VARS[EXPAND_API] $ZPWR_VARS[EXPAND_API]" >&2
    return 1
fi

if ! source $ZPWR_VARS[EXPAND_LIB];then
    echo "failed source ZPWR_VARS[EXPAND_LIB] $ZPWR_VARS[EXPAND_LIB]" >&2
    return 1
fi


#{{{                    MARK:regex
#**************************************************************
ZPWR_VARS[builtinSkips]='(builtin|command|exec|eval|noglob|-)'

ZPWR_VARS[blacklistUser]=""
if (( $#ZPWR_EXPAND_BLACKLIST )); then
    ZPWR_VARS[blacklistUser]="^(${(j:|:)ZPWR_EXPAND_BLACKLIST})$"
fi

(){
    local ws='[:space:]'
    local l='[:graph:]'
    ZPWR_VARS[startQuoteRegex]='(\$''|[\\"''])*'
    ZPWR_VARS[endQuoteRegex]='["'']*'
    local sq=${ZPWR_VARS[startQuoteRegex]}
    local eq=${ZPWR_VARS[endQuoteRegex]}

    ZPWR_VARS[blacklistFirstPosRegex]='^(omz_history|podman|grc|_z|zshz|cd|hub|_zsh_tmux_|_rails_|_rake_|mvn-or|gradle-or|noglob |rlwrap ).*$'

    ZPWR_VARS[blacklistSubcommandPositionRegex]='^(cargo|jenv|svn|git|ng|go|pod|docker|kubectl|rndc|yarn|npm|pip[0-9\.]*|bundle|rails|gem|nmcli|brew|apt|dnf|yum|zypper|pacman|service|proxychains[0-9\.]*|zpwr|zm|zd|zg|zinit)$'
    # the main regex to match x=1 \builtin* 'command'* '"sudo"' -* y=2 \env* -* z=3 cmd arg1 arg2 etc

    ZPWR_VARS[continueFirstPositionRegexNoZpwr]="^([$ws]*)((${sq}(-|nocorrect|time)${eq}[$ws]+)*(${sq}builtin${eq}[$ws]+)*(${sq}${ZPWR_VARS[builtinSkips]}${eq}[$ws]+)*)?(${sq}[sS][uU][dD][oO]${eq}([$ws]+)(${sq}(-[ABbEHnPSis]+${eq}[$ws]*|-[CghpTu][$ws=]+[$l]*${eq}[$ws]+|--${eq})*)*|${sq}[eE][nN][vV]${eq}[$ws]+(${sq}-[iv]+${eq}[$ws]*|-[PSu][$ws=]+[$l]*${eq}[$ws]+|--${eq})*|${sq}([nN][iI][cC][eE]|[tT][iI][mM][eE]|[nN][oO][hH][uU][pP]|[rR][lL][wW][rR][aA][pP])${eq}[$ws]+)*([$ws]*)(.*)$"
}



#}}}***********************************************************

#}}}***********************************************************

#{{{                    MARK:keybind
#**************************************************************

zle -N zpwrExpandSupernaturalSpace
zle -N zpwrExpandTerminateSpace
zle -N zpwrExpandSupernaturalEnter

if [[ $ZPWR_EXPAND != false ]]; then
    bindkey -M viins " " zpwrExpandSupernaturalSpace
    bindkey -M viins "^@" zpwrExpandTerminateSpace
    bindkey -M viins "^M" zpwrExpandSupernaturalEnter

    bindkey -M emacs " " zpwrExpandSupernaturalSpace
    bindkey -M emacs "^@" zpwrExpandTerminateSpace
    bindkey -M emacs "^M" zpwrExpandSupernaturalEnter
fi



zle -N zpwrExpandGlobalAliases

bindkey '\e^E' zpwrExpandGlobalAliases
#}}}***********************************************************
