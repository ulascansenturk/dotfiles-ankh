#!/bin/bash

CONFIG_DIR=$HOME/.config
mkdir -p $CONFIG_DIR/yabai
mkdir -p $CONFIG_DIR/skhd

cp .alacritty.yml $HOME
cp skhdrc $CONFIG_DIR/skhd

# Check if Homebrew is installed
if ! command -v brew &>/dev/null; then
	echo "Homebrew is not installed on this system. Installing now..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
	echo "Homebrew is already installed on this system."
fi

# Install packages from the Brewfile
if [ -e Brewfile ]; then
	echo "Installing packages from Brewfile..."
	brew bundle install 2>&1 | awk '/^==> Installing/ {printf "\r%s", $0}'
fi

# Check if Oh My Zsh is installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
	echo "Oh My Zsh is not installed on this system. Installing now..."
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
	echo "Oh My Zsh is already installed on this system."
	if [ -e "$HOME/.zshrc" ]; then
		read -p "A .zshrc file already exists in the home directory. Overwrite it? [y/n] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			cp .zshrc $HOME
		fi
	else
		cp .zshrc $HOME
	fi
	cp -R .oh-my-zsh $HOME
fi

echo "Configuration files and packages installed!"
