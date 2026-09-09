/**
 * The console's information architecture.
 *
 * Thirteen flat links in a top bar made people hunt. Grouping them by the
 * question being asked — what is happening today, who is the client, how is the
 * team paid, how is the business set up — means a destination can be found by
 * reasoning rather than by memory.
 *
 * `roles` is presentation only; the API enforces access. A link is hidden
 * rather than shown-and-refused, because offering something that will 403 is
 * its own kind of guessing.
 */
export type Role = 'owner' | 'manager' | 'staff';

export interface NavItem {
  path: string;
  label: string;
  icon: string;
  /** What this screen is for, shown as the page subtitle. */
  description: string;
  roles: Role[];
}

export interface NavGroup {
  label: string;
  items: NavItem[];
}

const ALL: Role[] = ['owner', 'manager', 'staff'];
const DESK: Role[] = ['owner', 'manager'];
const OWNER: Role[] = ['owner'];

export const NAV_GROUPS: NavGroup[] = [
  {
    label: 'Today',
    items: [
      {
        path: '/dashboard',
        label: 'Dashboard',
        icon: 'space_dashboard',
        description: "How today is going at this location, at a glance.",
        roles: ALL,
      },
      {
        path: '/schedule',
        label: 'Schedule',
        icon: 'calendar_month',
        description: 'Every room and therapist, hour by hour.',
        roles: ALL,
      },
    ],
  },
  {
    label: 'Clients',
    items: [
      {
        path: '/clients',
        label: 'Clients',
        icon: 'group',
        description: 'One record per client, shared across all four locations.',
        roles: DESK,
      },
      {
        path: '/approvals',
        label: 'Approvals',
        icon: 'approval',
        description: 'Requests waiting on you — therapist requests auto-approve after 45 minutes.',
        roles: DESK,
      },
    ],
  },
  {
    label: 'Sales',
    items: [
      {
        path: '/gift-cards',
        label: 'Gift cards',
        icon: 'card_giftcard',
        description: 'Sell a card, look one up, and read its ledger.',
        roles: DESK,
      },
      {
        path: '/membership',
        label: 'Memberships',
        icon: 'loyalty',
        description: 'Members, their credits, and cancellations.',
        roles: DESK,
      },
    ],
  },
  {
    label: 'Team',
    items: [
      {
        path: '/admin/roster',
        label: 'Roster',
        icon: 'event_available',
        description: 'Draft and publish shifts. A shift is not bookable until it is published.',
        roles: DESK,
      },
      {
        path: '/admin/staff',
        label: 'Staff',
        icon: 'badge',
        description: 'Onboard therapists, set what they are qualified for, and set their pay.',
        roles: OWNER,
      },
      {
        path: '/earnings',
        label: 'Earnings',
        icon: 'payments',
        description: 'What each therapist earned, by pay period.',
        roles: OWNER,
      },
    ],
  },
  {
    label: 'Business',
    items: [
      {
        path: '/reports',
        label: 'Reports',
        icon: 'monitoring',
        description: 'Revenue, liabilities and fees — kept separate on purpose.',
        roles: OWNER,
      },
      {
        path: '/admin/services',
        label: 'Services',
        icon: 'spa',
        description: 'The menu and what each service costs at each location.',
        roles: OWNER,
      },
      {
        path: '/admin/location',
        label: 'Location',
        icon: 'store',
        description: 'Opening hours, holidays, rooms, and rooms taken out of service.',
        roles: OWNER,
      },
    ],
  },
];

export function groupsFor(role: string | undefined): NavGroup[] {
  if (!role) return [];
  return NAV_GROUPS.map((g) => ({
    ...g,
    items: g.items.filter((i) => i.roles.includes(role as Role)),
  })).filter((g) => g.items.length > 0);
}

/** The page subtitle comes from the same place as the nav label. */
export function describe(path: string): { label: string; description: string } | undefined {
  for (const g of NAV_GROUPS) {
    const hit = g.items.find((i) => i.path === path);
    if (hit) return { label: hit.label, description: hit.description };
  }
  return undefined;
}
