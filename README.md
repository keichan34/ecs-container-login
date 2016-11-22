# ecs-container-login

## Usage

1. `./ecr-container-login.sh`
2. Pick the service
3. Pick the task within the service
4. Pick the container name within the task (if there is more than one container defined)
5. ecr-container-login will exec bash inside that container

## Dependencies

(can all be installed with Homebrew)

* [aws-cli](https://aws.amazon.com/cli/)
* [jq](https://stedolan.github.io/jq/)
* [peco](https://github.com/peco/peco)

