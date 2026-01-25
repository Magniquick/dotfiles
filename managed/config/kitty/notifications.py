#!/usr/bin/env python
# from https://github.com/kovidgoyal/kitty/blob/master/docs/notifications.py
# A sample script to process notifications. Save it as
# ~/.config/kitty/notifications.py


from kitty.notifications import NotificationCommand


# def log_notification(nc: NotificationCommand) -> None:
#     # Log notifications to /tmp/notifications-log.txt
#     with open('/tmp/notifications.log', 'a') as log:
#         print(f'title: {nc.title}', file=log)
#         print(f'body: {nc.body}', file=log)
#         print(f'app: {nc.application_name}', file=log)
#         print(f'types: {nc.notification_types}', file=log)
#         print(f'all: {nc}', file=log)
#         print('\n', file=log)


# def on_notification_activated(nc: NotificationCommand, which: int) -> None:
#     # do something when this notification is activated (clicked on)
#     # remember to assign this to the on_activation field in main()
#     pass


def main(nc: NotificationCommand) -> bool:
    '''
    This function should return True to filter out the notification
    '''
    # log_notification(nc)

    # filter out notifications from openai/codex and edit them.
    if nc.title.startswith('Approval requested: '):
        nc.body = nc.title.lstrip('Approval requested: ')
        nc.title = 'Codex: Approval requested'
        nc.application_name = 'openai-codex'

    # dont filter out this notification
    return False
