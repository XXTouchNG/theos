__THEOS_RULES_MK_VERSION := 1k
ifneq ($(__THEOS_RULES_MK_VERSION),$(__THEOS_COMMON_MK_VERSION))
all::
	@echo "Theos version mismatch! common.mk [version $(or $(__THEOS_COMMON_MK_VERSION),0)] loaded in tandem with rules.mk [version $(or $(__THEOS_RULES_MK_VERSION),0)] Check that \$$\(THEOS\) is set properly!" >&2; exit 1
endif

# Determine whether we are on a modern enough version of make for us to enable parallel building.
# --output-sync was added in make 4.0; output is hard to read without it. Xcode includes make 3.81.
ifeq ($(_THEOS_IS_MAKE_GT_4_0),)
_THEOS_IS_MAKE_GT_4_0 := $(call __vercmp,$(MAKE_VERSION),gt,4.0)
endif

ifeq ($(THEOS_USE_PARALLEL_BUILDING),)
ifeq ($(_THEOS_IS_MAKE_GT_4_0)$(THEOS_IGNORE_PARALLEL_BUILDING_NOTICE),)
ifneq ($(shell $(or $(_THEOS_PLATFORM_GET_LOGICAL_CORES),:)),1)
all::
	@$(PRINT_FORMAT) "Build may be slow as Theos isn’t using all available CPU cores on this computer. Consider upgrading GNU Make: https://theos.dev/docs/parallel-building"
endif
endif
THEOS_USE_PARALLEL_BUILDING := $(_THEOS_IS_MAKE_GT_4_0)
endif
export THEOS_USE_PARALLEL_BUILDING

# This is effectively THEOS_USE_PARALLEL_BUILDING canonicalized
ifeq ($(_THEOS_INTERNAL_USE_PARALLEL_BUILDING),)
_THEOS_INTERNAL_USE_PARALLEL_BUILDING := $(call __theos_bool,$(THEOS_USE_PARALLEL_BUILDING))
endif
export _THEOS_INTERNAL_USE_PARALLEL_BUILDING

# certain conditions need to execute, semantically, when we're
# running the first `all`. This is usually when MAKELEVEL == 0
# but is in fact MAKELEVEL == 1 if we're running `troubleshoot`
_THEOS_TOP_ALL_MAKELEVEL := $(if $(THEOS_IS_TROUBLESHOOTING),1,0)
ifeq ($(MAKELEVEL),$(_THEOS_TOP_ALL_MAKELEVEL))
_THEOS_IS_TOP_ALL := $(_THEOS_TRUE)
endif

ifeq ($(MAKELEVEL)$(_THEOS_INTERNAL_USE_PARALLEL_BUILDING),0$(_THEOS_TRUE))
# If jobs haven’t already been specified, and we know how to get the number of logical cores on this
# platform, set jobs to the logical core count (CPU cores multiplied by threads per core).
ifneq ($(_THEOS_PLATFORM_GET_LOGICAL_CORES),)
	MAKEFLAGS += -j$(shell $(_THEOS_PLATFORM_GET_LOGICAL_CORES)) -Otarget
endif
endif

_THEOS_SWIFT_AUXILIARY_DIR = $(_THEOS_LOCAL_DATA_DIR)/swift
_THEOS_SWIFT_MUTEX_FILE = $(_THEOS_SWIFT_AUXILIARY_DIR)/output.lock
export _THEOS_SWIFT_MARKERS_DIR = $(_THEOS_SWIFT_AUXILIARY_DIR)/markers

ifeq ($(_THEOS_INTERNAL_USE_PARALLEL_BUILDING),$(_THEOS_TRUE))
export _THEOS_SWIFT_MUTEX = $(_THEOS_SWIFT_MUTEX_FILE)
else
export _THEOS_SWIFT_MUTEX = -
endif

.PHONY: all before-all internal-all after-all \
	clean before-clean internal-clean after-clean \
	clean-packages before-clean-packages internal-clean-packages after-clean-packages \
	before-commands commands \
	update-theos spm
ifeq ($(THEOS_BUILD_DIR),.)
all:: $(_THEOS_BUILD_SESSION_FILE) before-all internal-all after-all
else
all:: $(THEOS_BUILD_DIR) $(_THEOS_BUILD_SESSION_FILE) before-all internal-all after-all
endif

clean:: before-clean internal-clean after-clean

do:: all package install

before-all::
# If the sysroot is set but doesn’t exist, bail out.
ifeq ($(SYSROOT),)
	$(ERROR_BEGIN) "A SYSROOT could not be found. For instructions on installing an SDK: https://theos.dev/docs/installation" $(ERROR_END)
else
ifneq ($(call __exists,$(SYSROOT)),$(_THEOS_TRUE))
	$(ERROR_BEGIN) "Your current SYSROOT, “$(SYSROOT)”, appears to be missing." $(ERROR_END)
endif
endif

# If a vendored path is missing, bail out.
ifneq ($(call __exists,$(THEOS_VENDOR_INCLUDE_PATH)/.git)$(call __exists,$(THEOS_VENDOR_LIBRARY_PATH)/.git),$(_THEOS_TRUE)$(_THEOS_TRUE))
	$(ERROR_BEGIN) "The vendor/include and/or vendor/lib directories are missing. Please run \`$(THEOS)/bin/update-theos\`. More information: https://theos.dev/install" $(ERROR_END)
endif

ifeq ($(call __exists,$(THEOS_LEGACY_PACKAGE_DIR)),$(_THEOS_TRUE))
ifneq ($(call __exists,$(THEOS_PACKAGE_DIR)),$(_THEOS_TRUE))
	@$(PRINT_FORMAT) "The \"debs\" directory has been renamed to \"packages\". Moving it." >&2
	$(ECHO_NOTHING)mv "$(THEOS_LEGACY_PACKAGE_DIR)" "$(THEOS_PACKAGE_DIR)"$(ECHO_END)
endif
endif

ifeq ($(_THEOS_IS_TOP_ALL),$(_THEOS_TRUE))
	$(ECHO_NOTHING)rm -rf $(_THEOS_SWIFT_AUXILIARY_DIR)$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(_THEOS_SWIFT_AUXILIARY_DIR) $(_THEOS_SWIFT_MARKERS_DIR)$(ECHO_END)
endif

internal-all::

after-all::

before-clean::

internal-clean::
	$(ECHO_CLEANING)rm -rf "$(subst $(_THEOS_OBJ_DIR_EXTENSION),,$(THEOS_OBJ_DIR))"$(ECHO_END)

ifeq ($(call __exists,$(_THEOS_BUILD_SESSION_FILE)),$(_THEOS_TRUE))
	$(ECHO_NOTHING)rm "$(_THEOS_BUILD_SESSION_FILE)"$(ECHO_END)
	$(ECHO_NOTHING)touch "$(_THEOS_BUILD_SESSION_FILE)"$(ECHO_END)
endif

ifeq ($(MAKELEVEL),0)
	$(ECHO_NOTHING)rm -rf "$(THEOS_STAGING_DIR)" "$(_THEOS_SWIFT_AUXILIARY_DIR)" "$(_THEOS_TMP_COMPILE_COMMANDS_FILE)"$(ECHO_END)
endif

after-clean::

ifeq ($(MAKELEVEL),0)
ifneq ($(THEOS_BUILD_DIR),.)
_THEOS_ABSOLUTE_BUILD_DIR = $(call __clean_pwd,$(THEOS_BUILD_DIR))
else
_THEOS_ABSOLUTE_BUILD_DIR = .
endif
else
_THEOS_ABSOLUTE_BUILD_DIR = $(strip $(THEOS_BUILD_DIR))
endif

clean-packages:: before-clean-packages internal-clean-packages after-clean-packages

before-clean-packages::

internal-clean-packages::
	$(ECHO_NOTHING)rm -rf $(THEOS_PACKAGE_DIR)/$(THEOS_PACKAGE_NAME)_*-*_$(THEOS_PACKAGE_ARCH).deb$(ECHO_END)
	$(ECHO_NOTHING)rm -rf $(THEOS_PACKAGE_DIR)/$(THEOS_PACKAGE_NAME)-*-*.$(THEOS_PACKAGE_ARCH).rpm$(ECHO_END)

after-clean-packages::

$(_THEOS_BUILD_SESSION_FILE):
	@mkdir -p $(_THEOS_LOCAL_DATA_DIR)

ifeq ($(call __exists,$(_THEOS_BUILD_SESSION_FILE)),$(_THEOS_FALSE))
	@touch $(_THEOS_BUILD_SESSION_FILE)
endif

.PRECIOUS: %.variables %.subprojects

%.variables: _INSTANCE = $(basename $(basename $*))
%.variables: _OPERATION = $(subst .,,$(suffix $(basename $*)))
%.variables: _TYPE = $(subst -,_,$(subst .,,$(suffix $*)))
%.variables: __SUBPROJECTS = $(strip $(call __schema_var_all,$(_INSTANCE)_,SUBPROJECTS))
%.variables:
	+@ \
abs_build_dir=$(_THEOS_ABSOLUTE_BUILD_DIR); \
if [[ "$(__SUBPROJECTS)" != "" ]]; then \
  $(PRINT_FORMAT_MAKING) "Making $(_OPERATION) in subprojects of $(_TYPE) $(_INSTANCE)"; \
  for d in $(__SUBPROJECTS); do \
    d="$${d%:*}"; \
    if [[ "$${abs_build_dir}" = "." ]]; then \
      lbuilddir="."; \
    else \
      lbuilddir="$${abs_build_dir}/$$d"; \
    fi; \
    if $(MAKE) -C $$d -f $(_THEOS_PROJECT_MAKEFILE_NAME) $(_THEOS_MAKEFLAGS) $(_OPERATION) \
        THEOS_BUILD_DIR="$$lbuilddir" \
       ; then\
       :; \
    else exit $$?; \
    fi; \
  done; \
 fi; \
$(PRINT_FORMAT_MAKING) "Making $(_OPERATION) for $(_TYPE) $(_INSTANCE)"; \
$(MAKE) -f $(_THEOS_PROJECT_MAKEFILE_NAME) $(_THEOS_MAKEFLAGS) \
	internal-$(_TYPE)-$(_OPERATION) \
	_THEOS_CURRENT_TYPE="$(_TYPE)" \
	THEOS_CURRENT_INSTANCE="$(_INSTANCE)" \
	_THEOS_CURRENT_OPERATION="$(_OPERATION)" \
	THEOS_BUILD_DIR="$(_THEOS_ABSOLUTE_BUILD_DIR)"

%.subprojects: _INSTANCE = $(basename $(basename $*))
%.subprojects: _OPERATION = $(subst .,,$(suffix $(basename $*)))
%.subprojects: _TYPE = $(subst -,_,$(subst .,,$(suffix $*)))
%.subprojects: __SUBPROJECTS = $(strip $(call __schema_var_all,$(_INSTANCE)_,SUBPROJECTS))
%.subprojects:
	+@ \
abs_build_dir=$(_THEOS_ABSOLUTE_BUILD_DIR); \
if [[ "$(__SUBPROJECTS)" != "" ]]; then \
  $(PRINT_FORMAT_MAKING) "Making $(_OPERATION) in subprojects of $(_TYPE) $(_INSTANCE)"; \
  for d in $(__SUBPROJECTS); do \
    d="$${d%:*}"; \
    if [[ "$${abs_build_dir}" = "." ]]; then \
      lbuilddir="."; \
    else \
      lbuilddir="$${abs_build_dir}/$$d"; \
    fi; \
    if $(MAKE) -C $$d -f $(_THEOS_PROJECT_MAKEFILE_NAME) $(_THEOS_MAKEFLAGS) $(_OPERATION) \
        THEOS_BUILD_DIR="$$lbuilddir" \
       ; then\
       :; \
    else exit $$?; \
    fi; \
  done; \
 fi

update-theos::
	@$(PRINT_FORMAT_MAKING) "Updating Theos"
	$(ECHO_NOTHING)$(THEOS_BIN_PATH)/update-theos$(ECHO_END)

troubleshoot::
	@$(PRINT_FORMAT) "Be sure to check the troubleshooting page at https://theos.dev/docs/troubleshooting first."
	@$(PRINT_FORMAT) "For support with build errors, ask on Discord: https://theos.dev/discord. If you think you've found a bug in Theos, check the issue tracker at: https://github.com/theos/theos/issues"
	@echo

ifeq ($(call __executable,gh),$(_THEOS_TRUE))
	@$(PRINT_FORMAT) "Creating a Gist containing the output of \`make clean all messages=yes\`…"
	+$(MAKE) -f $(_THEOS_PROJECT_MAKEFILE_NAME) --no-print-directory --no-keep-going clean all messages=yes COLOR=no THEOS_IS_TROUBLESHOOTING=1 2>&1 | tee /dev/tty | gh gist create - -d "Theos troubleshoot output"
else
	$(ERROR_BEGIN) "You don't have the GitHub CLI installed. For more information, refer to: https://cli.github.com/" $(ERROR_END)
endif

# The SPM config is a simple key-value file used to pass build settings to Package.swift.
# Each line is either empty or starts with a (unique) key, followed by an equals sign, 
# followed by the key's value.
spm::
	@$(PRINT_FORMAT_MAKING) "Creating SPM config"
	@mkdir -p $(_THEOS_LOCAL_DATA_DIR)
	$(ECHO_NOTHING)rm -f $(_THEOS_SPM_CONFIG_FILE)$(ECHO_END)
	$(ECHO_NOTHING)echo "theos=$(THEOS)" >> $(_THEOS_SPM_CONFIG_FILE)$(ECHO_END)
	$(ECHO_NOTHING)echo "sdk=$(SYSROOT)" >> $(_THEOS_SPM_CONFIG_FILE)$(ECHO_END)
	$(ECHO_NOTHING)echo "deploymentTarget=$(_THEOS_TARGET_OS_DEPLOYMENT_VERSION)" >> $(_THEOS_SPM_CONFIG_FILE)$(ECHO_END)
	$(ECHO_NOTHING)echo "swiftResourceDir=$(_THEOS_TARGET_SWIFT_RESOURCE_DIR)" >> $(_THEOS_SPM_CONFIG_FILE)$(ECHO_END)

before-commands::
	@: $(eval export THEOS_GEN_COMPILE_COMMANDS=$(_THEOS_TRUE))

commands:: before-commands clean all
	@$(PRINT_FORMAT_MAKING) "Writing $(notdir $(_THEOS_COMPILE_COMMANDS_FILE))"
	$(ECHO_NOTHING)mv -f $(_THEOS_TMP_COMPILE_COMMANDS_FILE) $(_THEOS_COMPILE_COMMANDS_FILE)$(ECHO_END)

$(eval $(call __mod,master/rules.mk))

ifeq ($(_THEOS_TOP_INVOCATION_DONE),$(_THEOS_FALSE))
export _THEOS_TOP_INVOCATION_DONE = 1
endif
