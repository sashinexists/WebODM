# Generated manually for Django 5.2 compatibility
# Date: 2025-10-28
# Changes:
# - NullBooleanField → BooleanField (removed in Django 4.0)
# - django.contrib.postgres.fields.JSONField → models.JSONField (moved to core in Django 3.1)

from django.db import migrations, models
import app.models.task


class Migration(migrations.Migration):

    dependencies = [
        ('app', '0044_task_console_link'),
    ]

    operations = [
        # PluginDatum: NullBooleanField → BooleanField
        migrations.AlterField(
            model_name='plugindatum',
            name='bool_value',
            field=models.BooleanField(blank=True, default=None, null=True, verbose_name='Bool value'),
        ),
        # PluginDatum: JSONField update (already models.JSONField, but ensuring proper definition)
        migrations.AlterField(
            model_name='plugindatum',
            name='json_value',
            field=models.JSONField(blank=True, default=None, null=True, verbose_name='JSON value'),
        ),
        # Preset: JSONField update
        migrations.AlterField(
            model_name='preset',
            name='options',
            field=models.JSONField(blank=True, default=list, help_text="Options that define this preset (same format as in a Task's options).", validators=[app.models.task.validate_task_options], verbose_name='Options'),
        ),
        # Task: JSONField updates (multiple fields)
        migrations.AlterField(
            model_name='task',
            name='options',
            field=models.JSONField(blank=True, default=dict, help_text='Options that are being used to process this task', validators=[app.models.task.validate_task_options], verbose_name='Options'),
        ),
        migrations.AlterField(
            model_name='task',
            name='potree_scene',
            field=models.JSONField(blank=True, default=dict, help_text='Serialized potree scene information used to save/load measurements and camera view angle', verbose_name='Potree Scene'),
        ),
        migrations.AlterField(
            model_name='task',
            name='orthophoto_bands',
            field=models.JSONField(blank=True, default=list, help_text='List of orthophoto bands', verbose_name='Orthophoto Bands'),
        ),
    ]
