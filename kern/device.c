/* device.c - device manager */
/*
 *  GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2002,2005,2007,2008  Free Software Foundation, Inc.
 *
 *  GRUB is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  GRUB is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with GRUB.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <grub/device.h>
#include <grub/disk.h>
#include <grub/net.h>
#include <grub/fs.h>
#include <grub/mm.h>
#include <grub/misc.h>
#include <grub/env.h>
#include <grub/partition.h>

grub_device_t
grub_device_open (const char *name)
{
  grub_disk_t disk = 0;
  grub_device_t dev = 0;

  if (! name)
    {
      name = grub_env_get ("root");
      if (*name == '\0')
	{
	  grub_error (GRUB_ERR_BAD_DEVICE, "no device is set");
	  goto fail;
	}
    }

  dev = grub_malloc (sizeof (*dev));
  if (! dev)
    goto fail;

  /* Try to open a disk.  */
  disk = grub_disk_open (name);
  if (! disk)
    goto fail;

  dev->disk = disk;
  dev->net = 0;	/* FIXME */

  return dev;

 fail:
  if (disk)
    grub_disk_close (disk);

  grub_free (dev);

  return 0;
}

grub_err_t
grub_device_close (grub_device_t device)
{
  if (device->disk)
    grub_disk_close (device->disk);

  grub_free (device);

  return grub_errno;
}

static char *g_current_device_name = NULL;

grub_err_t
set_current_device_being_opened (const char *name)
{	
	if (g_current_device_name)
		grub_free(g_current_device_name);	

	if (name)
		g_current_device_name = grub_strdup(name);
	else
		g_current_device_name = NULL;

	return GRUB_ERR_NONE;
}

const char *
get_current_device_being_opened (void)
{	
	return g_current_device_name;
}

int
grub_device_iterate (int (*hook) (const char *name))
{
  auto int iterate_disk (const char *disk_name);
  auto int iterate_partition (grub_disk_t disk,
			      const grub_partition_t partition);

  struct part_ent
  {
    struct part_ent *next;
    char name[0];
  } *ents;

  int iterate_disk (const char *disk_name)
    {
      grub_device_t dev;

	  if (g_current_device_name && grub_strcasecmp (disk_name, g_current_device_name) == 0)
	  { 
		  // this prevents infinite loop, e.g., vhd vhd0 (UUID=uuid)/xp.vhd
		  return 0;
	  }

      if (hook (disk_name))
	return 1;	  
      dev = grub_device_open (disk_name);
      if (! dev)
	return 0;

      if (dev->disk && dev->disk->has_partitions)
	{
	  struct part_ent *p;
	  int ret = 0;

	  ents = NULL;
	  (void) grub_partition_iterate (dev->disk, iterate_partition);
	  grub_device_close (dev);

	  p = ents;
	  while (p != NULL)
	    {
	      struct part_ent *next = p->next;

	      if (!ret)
		ret = hook (p->name);
	      grub_free (p);
	      p = next;
	    }

	  return ret;
	}

      grub_device_close (dev);
      return 0;
    }

  int iterate_partition (grub_disk_t disk, const grub_partition_t partition)
    {
      char *partition_name;
      struct part_ent *p;

      partition_name = grub_partition_get_name (partition);
      if (! partition_name)
	return 1;

      p = grub_malloc (sizeof (p->next) + grub_strlen (disk->name) + 1 +
		       grub_strlen (partition_name) + 1);
      if (!p)
	{
	  grub_free (partition_name);
	  return 1;
	}

      grub_sprintf (p->name, "%s,%s", disk->name, partition_name);
      grub_free (partition_name);

      p->next = ents;
      ents = p;

      return 0;
    }

  /* Only disk devices are supported at the moment.  */
  return grub_disk_dev_iterate (iterate_disk);
}
