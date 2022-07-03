

# Information on Molecule 
Molecule is a complete testing framework that helps you develop and test Ansible roles, which allows you to focus on role content instead of focusing on managing testing infrastructure

# Links
## Docs
https://molecule.readthedocs.io/en/latest/
https://molecule.readthedocs.io/en/latest/usage.html

# Usage

## Requierments 

- python 
- docker 
- ansible 
- molecule package

```
python3 -m pip install molecule 
```

## Files 

### converge.yml 
- something like the main playbook
### molecule.yml
- configure which docker image should be used
### prepare.yml
- The prepare playbook executes actions which bring the system to a given state prior to converge. It is executed after create, and only once for the duration of the instances life. <br> 
This can be used to bring instances into a particular state, prior to testing. For example installing openssh onto the container to be able to login via ssh. 
### verify.yml

<br>


## Preparation 
- check in converge file that user specified under vars has pub key (otherwise role cant be tested - currently used: technicaluser)


## Execution 
### Process
- Docker container gets created (config molecule.yml)  "PLAY [Create]"
- prepare.yml playbook is run "PLAY [Prepare molecule]"
- converge.yml playbook is run "PLAY [Converge]"
- verify.yml playbook is run 
- Docker conatiner gets destroyed "PLAY [Destroy]" 

### Commands
```
cd infra-ansible-collections 
# Targets the default scenario -> looks more like a playbook, container does not get destroyed
molecule converge  
# Targets the default scenario -> slower, container gets destroyed after run 
molecule test 
# like molecule test, but container doesn't get destroyed 
molecule test --destroy=never   
# Debug mode
molecule --debug test
# Destroy container 
molecule destroy 
```

<br>

### Change scenario 
By default the molecule/default will be executed. We also have another config. They have to be different since the docker image and other configurations have to be different from the rest ni default. If you want to run the molecule/haproy config use: 
<br>
```molecule test -s haproxy```

<br>
## Add a certain task or role

 ```
 - name: Converge
   hosts: all
    tasks:
      - name: "Include role: users"
        include_role:
          name: "users"
      - name: "Include role: basic"
        include_role: 
          name: "basic"
```

<br>

## Providing Vars 
- Vars should be provided in the converge.yml 

 ```
  vars:
      present_groups:
        - name: testgroup1
          gid: 1500
          hosts:
            - localhost
            - instance
```

<br>

# Extra Information 


## Docker Conainter
### Get IP address from Docker Container 
```
sudo docker inspect -f "{{ .NetworkSettings.IPAddress }}" CONTAINER_ID
```
### Log into shell of container
```
docker exec -it CONTAINER_ID /bin/bash
```

## Creating a default new molecule dir
```
molecule init role molecule --driver-name docker
```
```
molecule
├── defaults
│   └── main.yml
├── files
├── handlers
│   └── main.yml
├── meta
│   └── main.yml
├── molecule
│   └── default
│       ├── converge.yml
│       ├── molecule.yml
│       └── verify.yml
├── README.md
├── tasks
│   └── main.yml
├── templates
├── tests
│   ├── inventory
│   └── test.yml
└── vars
    └── main.yml
```

## Errors and Solutions
```
 CRITICAL 'molecule/default/molecule.yml' glob failed.  Exiting.
 -> means you are not in the right dir! (should be infra-ansible-collections)
```

```
TASK [Gathering Facts] *********************************************************
fatal: [instance]: UNREACHABLE! => {"changed": false, "msg": "Failed to create temporary directory.In some cases, you may have been able to authenticate and did not have permissions on the target directory. Consider changing the remote tmp path in ansible.cfg to a path rooted in \"/tmp\", for more error information use -vvv. Failed command was: ( umask 77 && mkdir -p \"` echo ~/.ansible/tmp `\"&& mkdir \"` echo ~/.ansible/tmp/ansible-tmp-1654157308.0831442-43046-12358645612532 `\" && echo ansible-tmp-1654157308.0831442-43046-12358645612532=\"` echo ~/.ansible/tmp/ansible-tmp-1654157308.0831442-43046-12358645612532 `\" ), exited with result 1", "unreachable": true}
```
-> run 'molecule destroy' before you 'molecule test' or 'molecule converge' 