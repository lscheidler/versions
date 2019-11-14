0.2.3 (2019-11-14)
==================

- bugfix: don't try to get docker versions, if docker isn't available

0.2.2 (2019-11-04)
==================

- catch Errno::EPERM, if not user, which created file

0.2.1 (2019-11-01)
==================

- added group\_ownership to set group ownership for generated files
- get access\_key\_id and secret\_access\_key from config file

0.2.0 (2019-11-01)
==================

- introduce plugins for following deployment types:
  - release directory (current, previous symlink)
  - docker image

0.1.0 (2019-08-27)
==================

- Initial release
