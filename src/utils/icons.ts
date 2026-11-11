import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';

// Nome válido de qualquer ícone do Ionicons — evita strings soltas e dá
// autocompletar em todo lugar que desenha um ícone.
export type IconName = ComponentProps<typeof Ionicons>['name'];
