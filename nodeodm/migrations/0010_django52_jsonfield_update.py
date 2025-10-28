# Generated manually for Django 5.2 compatibility
# Date: 2025-10-28
# Changes:
# - django.contrib.postgres.fields.JSONField → models.JSONField (moved to core in Django 3.1)

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('nodeodm', '0009_auto_20210610_1850'),
    ]

    operations = [
        # ProcessingNode: JSONField update
        migrations.AlterField(
            model_name='processingnode',
            name='available_options',
            field=models.JSONField(default=dict, help_text='Description of the options that can be used for processing', verbose_name='Available Options'),
        ),
    ]
