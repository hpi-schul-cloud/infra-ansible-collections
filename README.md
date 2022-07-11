
# These are our Ansible Roles 
They are used in the infra-schulcloud repo and installed over the Makefile


## Testing via Molecule 
Roles should be tested beforehand with molecule
<br>
Note: Some tasks may throw an error when tested with molecule. This is because molecule tests the config in a docker image and the image may differ from the target system. 
-> use the "molecule-notest" tag so they get skipped when executed with molecule 