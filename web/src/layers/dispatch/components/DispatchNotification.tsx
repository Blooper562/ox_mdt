import React from 'react';
import { Call } from '../../../typings';
import { ActionIcon, Badge, createStyles, Divider, Group, Stack, Text, Tooltip, Transition } from '@mantine/core';
import { IconCar, IconClock, IconLink, IconMap2, IconMapPin, IconSteeringWheel } from '@tabler/icons-react';
import dayjs from 'dayjs';
import NotificationInfo from './NotificationInfo';
import { useNuiEvent } from '../../../hooks/useNuiEvent';
import { useTimeout } from '@mantine/hooks';

interface Props {
  call: Call;
  setQueue: React.Dispatch<React.SetStateAction<Call[]>>;
}

const useStyles = createStyles((theme) => ({
  notification: {
    width: '100%',
    height: 'fit-content',
    backgroundColor: theme.colors.durple[6],
    color: theme.colors.dark[0],
    borderRadius: theme.radius.md,
    padding: theme.spacing.md,
    opacity: 1,
    boxShadow: theme.shadows.md,
    zIndex: 0,
  },
}));

const DispatchNotification: React.FC<Props> = ({ call, setQueue }) => {
  const { classes } = useStyles();
  const timeout = useTimeout(() => setQueue((prev) => prev.filter((queueCall) => queueCall.id !== call.id)), 5000, {
    autoInvoke: true,
  });

  React.useEffect(() => {
    return () => timeout.clear();
  }, []);

  return (
    <Stack className={classes.notification} spacing={6}>
      <Stack spacing={0}>
        <Group position="apart">
          <Text size="lg">{call.offense}</Text>
          <Group spacing={6}>
            <Tooltip label="Attach" position="top">
              <ActionIcon variant="light" color="blue">
                <IconLink size={20} />
              </ActionIcon>
            </Tooltip>
            <Tooltip label="Add waypoint" position="top">
              <ActionIcon variant="light" color="blue">
                <IconMapPin size={20} />
              </ActionIcon>
            </Tooltip>
          </Group>
        </Group>
        <Badge variant="light" color="blue" sx={{ alignSelf: 'flex-start' }} radius="sm">
          {call.code}
        </Badge>
      </Stack>
      <Divider />
      <Group spacing="xs">
        <NotificationInfo label={dayjs(call.info.time).fromNow()} icon={IconClock} />
        {call.info.location && <NotificationInfo icon={IconMap2} label={call.info.location} />}
        {call.info.plate && <NotificationInfo icon={IconSteeringWheel} label={call.info.plate} />}
        {call.info.vehicle && <NotificationInfo icon={IconCar} label={call.info.vehicle} />}
      </Group>
    </Stack>
  );
};

export default React.memo(DispatchNotification);