#ifndef WCM_DELETE_PATH_H
#define WCM_DELETE_PATH_H
int wcm_path_valid(const char *path);
int wcm_path_equal_alias(const char *a, const char *b);
int wcm_open_directory(const char *root, const char *leaf, const char **stage, int *error);
#endif
