# ubuntu-proxy
Setup ubuntu proxy in one command.
If you are a developer living in mainland China, you will definitely be troubled by network problems. Especially when deploying Docker on a newly purchased cloud server, you need to manually configure some proxies. This repository organizes some common configurations into scripts
## Prerequisites
- [Hysteria2](https://v2.hysteria.network/zh/docs/getting-started/Client/) client configuration file

## How to use
- Download repository

    `git clone https://github.com/zomco/ubuntu-proxy.git`

    `cd ubuntu-proxy`

- Update configuration

    `nano config.yaml`

    // replace with your own configuration

- Run
    `sudo chmod +x ./hysteria-linxu-amd64`
  
    `sudo chmod +x ./proxy.sh`

    `./proxy.sh set` 

## Troubleshooting
If you have any problems, please [open an issue](https://github.com/zomco/ubuntu-proxy/issues)
