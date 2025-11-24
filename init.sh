#!/bin/bash

/workspace/main/.devcontainer/setup.sh

chmod +x /workspace/main/.devcontainer/setup.personal.sh
/workspace/main/.devcontainer/setup.personal.sh

# alias terraform to tf
alias tf="terraform" >> ~/.bashrc
source ~/.bashrc