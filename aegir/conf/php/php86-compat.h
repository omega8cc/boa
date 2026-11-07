/*
 * Names PHP 8.6 removed from its headers, defined as PHP 8.5 defined them
 * (Zend/zend_ini.h and Zend/zend_variables.h), for extension releases that
 * still call them. INI_STR keeps 8.5's char * type (8.6's zend_ini_string_ex
 * returns const char *). BOA passes this file with "-include" to PHP 8.6
 * extension builds only: PHP 8.5 and older define these names themselves.
 */
#define INI_INT(name) zend_ini_long((name), strlen(name), 0)
#define INI_FLT(name) zend_ini_double((name), strlen(name), 0)
#define INI_STR(name) ((char *) zend_ini_string_ex((name), strlen(name), 0, NULL))
#define INI_BOOL(name) ((bool) INI_INT(name))
#define zval_dtor(zvalue) zval_ptr_dtor_nogc(zvalue)
