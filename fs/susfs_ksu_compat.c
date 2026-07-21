// SPDX-License-Identifier: GPL-2.0

#include <linux/compiler.h>
#include <linux/fs.h>
#include <linux/mutex.h>
#include <linux/susfs.h>
#include <linux/types.h>
#include <linux/jump_label.h>
#include <linux/utsname.h>
#include <linux/version.h>

/*
 * SUSFS compatibility / fallback symbols for KernelSU-Next
 */

// 1. Static keys and variables required by the main kernel patches
struct static_key_false ksu_input_hook_key_false __attribute__((weak)) = STATIC_KEY_FALSE_INIT;
EXPORT_SYMBOL_GPL(ksu_input_hook_key_false);

u32 __weak susfs_ksu_sid;
EXPORT_SYMBOL_GPL(susfs_ksu_sid);

u32 __weak susfs_priv_app_sid;
EXPORT_SYMBOL_GPL(susfs_priv_app_sid);

DEFINE_STATIC_KEY_TRUE(susfs_avc_log_spoofing_key_true);
EXPORT_SYMBOL_GPL(susfs_avc_log_spoofing_key_true);

DEFINE_STATIC_KEY_TRUE(susfs_set_fake_cmdline_or_bootconfig_key_true);
EXPORT_SYMBOL_GPL(susfs_set_fake_cmdline_or_bootconfig_key_true);

bool susfs_hide_sus_mnts_for_non_su_procs = false;
EXPORT_SYMBOL_GPL(susfs_hide_sus_mnts_for_non_su_procs);

DEFINE_STATIC_KEY_FALSE(susfs_set_sdcard_android_data_decrypted_key_false);
EXPORT_SYMBOL_GPL(susfs_set_sdcard_android_data_decrypted_key_false);

struct static_key_false ksu_init_rc_hook_key_false __attribute__((weak)) = STATIC_KEY_FALSE_INIT;
EXPORT_SYMBOL_GPL(ksu_init_rc_hook_key_false);

DEFINE_STATIC_KEY_TRUE(susfs_set_uname_key_true);
EXPORT_SYMBOL_GPL(susfs_set_uname_key_true);

// 2. Weak functions implementing the hooks or stubs

extern bool is_ksu_domain(void) __weak;

bool __weak susfs_is_current_ksu_domain(void)
{
	if (is_ksu_domain)
		return is_ksu_domain();
	return false;
}
EXPORT_SYMBOL_GPL(susfs_is_current_ksu_domain);

int __weak ksu_handle_devpts(struct inode *inode)
{
	return 0;
}
EXPORT_SYMBOL_GPL(ksu_handle_devpts);

void __weak ksu_handle_vfs_fstat(int fd, loff_t *kstat_size_ptr)
{
}
EXPORT_SYMBOL_GPL(ksu_handle_vfs_fstat);

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0)
int __weak ksu_handle_stat(int *dfd, struct filename **filename, int *flags)
{
	return 0;
}
#else
int __weak ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags)
{
	return 0;
}
#endif
EXPORT_SYMBOL_GPL(ksu_handle_stat);

int __weak ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags)
{
	return 0;
}
EXPORT_SYMBOL_GPL(ksu_handle_execveat_sucompat);

int __weak ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags)
{
	return 0;
}
EXPORT_SYMBOL_GPL(ksu_handle_execveat);

void __weak ksu_handle_sys_read(unsigned int fd)
{
}
EXPORT_SYMBOL_GPL(ksu_handle_sys_read);

int __weak ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *__unused_flags)
{
	return 0;
}
EXPORT_SYMBOL_GPL(ksu_handle_faccessat);

#ifndef KSU_INSTALL_MAGIC1
#define KSU_INSTALL_MAGIC1 0xDEADBEEF
#endif

static DEFINE_MUTEX(susfs_bootstrap_lock);
static bool susfs_bootstrap_done __read_mostly;

static void susfs_bootstrap_once(void)
{
	if (READ_ONCE(susfs_bootstrap_done))
		return;

	mutex_lock(&susfs_bootstrap_lock);
	if (!susfs_bootstrap_done) {
		susfs_init();
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
		susfs_start_sdcard_monitor_fn();
#endif
		WRITE_ONCE(susfs_bootstrap_done, true);
	}
	mutex_unlock(&susfs_bootstrap_lock);
}

int __weak ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user *arg)
{
	if ((u32)magic1 != KSU_INSTALL_MAGIC1 || (u32)magic2 != SUSFS_MAGIC)
		return 1;

	susfs_bootstrap_once();

	switch (cmd) {
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	case CMD_SUSFS_ADD_SUS_PATH:
		susfs_add_sus_path(&arg);
		return 0;
	case CMD_SUSFS_ADD_SUS_PATH_LOOP:
		susfs_add_sus_path_loop(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS:
		susfs_set_hide_sus_mnts_for_non_su_procs(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
	case CMD_SUSFS_ADD_SUS_KSTAT:
	case CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY:
		susfs_add_sus_kstat(&arg);
		return 0;
	case CMD_SUSFS_UPDATE_SUS_KSTAT:
		susfs_update_sus_kstat(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	case CMD_SUSFS_SET_UNAME:
		susfs_set_uname(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
	case CMD_SUSFS_ENABLE_LOG:
		susfs_enable_log(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	case CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG:
		susfs_set_cmdline_or_bootconfig(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
	case CMD_SUSFS_ADD_OPEN_REDIRECT:
		susfs_add_open_redirect(&arg);
		return 0;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	case CMD_SUSFS_ADD_SUS_MAP:
		susfs_add_sus_map(&arg);
		return 0;
#endif
	case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING:
		susfs_set_avc_log_spoofing(&arg);
		return 0;
	case CMD_SUSFS_SHOW_ENABLED_FEATURES:
		susfs_get_enabled_features(&arg);
		return 0;
	case CMD_SUSFS_SHOW_VARIANT:
		susfs_show_variant(&arg);
		return 0;
	case CMD_SUSFS_SHOW_VERSION:
		susfs_show_version(&arg);
		return 0;
	default:
		return 1;
	}
}
EXPORT_SYMBOL_GPL(ksu_handle_sys_reboot);
