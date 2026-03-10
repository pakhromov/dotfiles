#!/usr/bin/env bash
set -e
IFS=$'\t'
OS="$(uname -s)"

# 变成数组
arrSelection=(${selection})

# 取第一个项目的父路径
parentPath=${arrSelection[0]%/*}

# 取父路径名字
parentName=${parentPath##*/}

# 处理相对路径
case "$OS" in
	Darwin) relativePath=$(grealpath --relative-to="${parentPath}" ${selection}) ;;
	Linux) relativePath=$(realpath --relative-to="${parentPath}" ${selection}) ;;
	*) echo "Unsupported operating system"; exit 1 ;;
esac

# 进入工作目录
cd ${parentPath}

# 使用用户提供的名字
packName="${archive_name}"

# 执行压缩
zip -r "${packName}".zip ${relativePath//$'\n'/$IFS}
