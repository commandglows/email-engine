"use client";

import type * as React from "react";
import { useEffect, useState } from "react";
import {
  Archive,
  ArrowLeft,
  Bell,
  Check,
  ChevronDown,
  Command,
  File,
  FileText,
  Forward,
  Inbox,
  Link2,
  ListFilter,
  MailOpen,
  MailPlus,
  MailQuestion,
  MailX,
  Paperclip,
  PenLine,
  Plus,
  Reply,
  Search,
  Send,
  Settings,
  ShoppingCart,
  Star,
  Tag,
  Trash2,
  LucideUser,
  Users,
  HelpCircle,
  Grid,
  ChevronLeft,
  ChevronRight,
  MoreVertical,
  Clock,
  FolderPlus,
  Minimize,
  Maximize2,
  X,
  ImageIcon,
  Smile,
} from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
} from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";

import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

// Types
type Folder = {
  id: string;
  name: string;
  icon: React.ElementType;
  count?: number;
};

type EmailLabel = {
  id: string;
  name: string;
  color: string;
};

type EmailAttachment = {
  id: string;
  name: string;
  size: string;
  type: string;
  url: string;
};

type Email = {
  id: string;
  from: {
    name: string;
    email: string;
    avatar?: string;
  };
  to: {
    name: string;
    email: string;
    avatar?: string;
  };
  subject: string;
  message: string;
  time: string;
  labels: string[];
  read: boolean;
  starred: boolean;
  important: boolean;
  attachments?: EmailAttachment[];
  thread?: Email[];
};

type User = {
  name: string;
  email: string;
  avatar?: string;
};

// Mock data
const currentUser: User = {
  name: "Alex Morgan",
  email: "alex@example.com",
  avatar: "/placeholder.svg?height=40&width=40",
};

const folders: Folder[] = [
  { id: "inbox", name: "Inbox", icon: Inbox, count: 128 },
  { id: "drafts", name: "Drafts", icon: File, count: 9 },
  { id: "sent", name: "Sent", icon: Send },
  { id: "starred", name: "Starred", icon: Star, count: 24 },
  { id: "important", name: "Important", icon: MailQuestion, count: 56 },
  { id: "trash", name: "Trash", icon: Trash2 },
  { id: "archive", name: "Archive", icon: Archive },
];

const categories: Folder[] = [
  { id: "social", name: "Social", icon: Users, count: 972 },
  { id: "updates", name: "Updates", icon: Bell, count: 342 },
  { id: "forums", name: "Forums", icon: Command, count: 128 },
  { id: "promotions", name: "Promotions", icon: Tag, count: 221 },
  { id: "shopping", name: "Shopping", icon: ShoppingCart, count: 8 },
];

const labels: EmailLabel[] = [
  { id: "work", name: "Work", color: "bg-blue-500" },
  { id: "personal", name: "Personal", color: "bg-green-500" },
  { id: "important", name: "Important", color: "bg-red-500" },
  { id: "travel", name: "Travel", color: "bg-amber-500" },
  { id: "meeting", name: "Meeting", color: "bg-purple-500" },
  { id: "finance", name: "Finance", color: "bg-emerald-500" },
  { id: "project", name: "Project", color: "bg-indigo-500" },
];

const attachments: EmailAttachment[] = [
  {
    id: "1",
    name: "Q4_Financial_Report.pdf",
    size: "2.4 MB",
    type: "pdf",
    url: "#",
  },
  {
    id: "2",
    name: "Project_Timeline.xlsx",
    size: "1.8 MB",
    type: "xlsx",
    url: "#",
  },
  {
    id: "3",
    name: "Team_Photo.jpg",
    size: "3.2 MB",
    type: "jpg",
    url: "#",
  },
];

const emails: Email[] = [
  {
    id: "1",
    from: {
      name: "Sophia White",
      email: "sophiawhite@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Team Dinner Next Week",
    message: `Hi Alex,

Let's have a team dinner next week to celebrate our success. We've achieved some significant milestones, and it's time to acknowledge our hard work and dedication.

I've made reservations at Bistro Garden for Thursday at 7:00 PM. The restaurant has a great ambiance and excellent menu options that should accommodate everyone's preferences.

Please confirm your availability and any dietary preferences. Looking forward to a fun and memorable dinner with the team!

Best regards,
Sophia`,
    time: "Today, 10:32 AM",
    labels: ["work", "meeting"],
    read: false,
    starred: true,
    important: true,
    attachments: [attachments[2]],
  },
  {
    id: "2",
    from: {
      name: "Daniel Johnson",
      email: "daniel@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Feedback Request on Q4 Financial Report",
    message: `Hello Alex,

I'd like your feedback on the latest Q4 financial report. We've made significant progress, and I value your input to ensure we're on the right track. 

The report shows a 15% increase in revenue compared to Q3, with particularly strong performance in our new product lines. However, there are some areas where we might need to adjust our strategy for the upcoming quarter.

I've attached the full report for your review. Could you please provide your thoughts by Friday?

Thanks,
Daniel`,
    time: "Yesterday, 4:15 PM",
    labels: ["work", "finance"],
    read: true,
    starred: false,
    important: true,
    attachments: [attachments[0]],
  },
  {
    id: "3",
    from: {
      name: "Ava Taylor",
      email: "ava@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Project Timeline Update",
    message: `Hi Alex,

Here's the updated timeline for our project. I've included all the key milestones and deadlines we discussed in our last meeting.

The development phase is scheduled to complete by the end of this month, followed by two weeks of testing. We should be ready for the soft launch by the 15th of next month.

Please review the attached timeline and let me know if you have any concerns or suggestions for adjustments.

Best,
Ava`,
    time: "May 10, 2:30 PM",
    labels: ["project", "work"],
    read: true,
    starred: true,
    important: false,
    attachments: [attachments[1]],
  },
  {
    id: "4",
    from: {
      name: "William Anderson",
      email: "william@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Product Launch Strategy Meeting",
    message: `Dear Alex,

I'd like to schedule a meeting to discuss our product launch strategy. The development team has made excellent progress, and we're on track for our planned release date.

During the meeting, we'll cover:
- Marketing campaign timeline
- Press release strategy
- Social media rollout
- Customer feedback collection methods

Would Wednesday at 2:00 PM work for you? If not, please suggest an alternative time.

Regards,
William`,
    time: "May 8, 11:20 AM",
    labels: ["meeting", "work", "important"],
    read: true,
    starred: false,
    important: true,
  },
  {
    id: "5",
    from: {
      name: "Mia Harris",
      email: "mia@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Vacation Plans for Next Month",
    message: `Hey Alex,

Just wanted to confirm our vacation plans for next month. I've booked the flights and accommodations as we discussed.

We'll be flying out on the 10th at 11:00 AM and returning on the 20th. The beach house looks amazing, and it's just a 5-minute walk from the ocean.

I've also made a list of activities and restaurants we might want to try while we're there. Let me know if you have any specific preferences!

Can't wait!
Mia`,
    time: "May 5, 9:45 AM",
    labels: ["personal", "travel"],
    read: true,
    starred: true,
    important: false,
  },
  {
    id: "6",
    from: {
      name: "James Wilson",
      email: "james@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Monthly Budget Review",
    message: `Hello Alex,

It's time for our monthly budget review. I've analyzed the expenses for the past month, and there are a few items I'd like to discuss.

Overall, we're within our projected budget, but there are a couple of areas where we might need to make adjustments. The marketing expenses were slightly higher than anticipated, but they've also yielded better results than expected.

Let me know when you're available to go through the details.

Best,
James`,
    time: "May 3, 3:20 PM",
    labels: ["finance", "work"],
    read: true,
    starred: false,
    important: true,
  },
  {
    id: "7",
    from: {
      name: "Emma Clark",
      email: "emma@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "Weekend Hiking Trip",
    message: `Hi Alex,

Are you still up for the hiking trip this weekend? The weather forecast looks perfect - sunny with a high of 75°F.

I've mapped out a trail that should take about 4 hours to complete, with some beautiful viewpoints along the way. We can meet at my place at 8:00 AM and drive together.

Don't forget to bring plenty of water and some snacks!

Cheers,
Emma`,
    time: "May 1, 10:15 AM",
    labels: ["personal"],
    read: true,
    starred: false,
    important: false,
  },
  {
    id: "8",
    from: {
      name: "Noah Martinez",
      email: "noah@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    to: {
      name: "Alex Morgan",
      email: "alex@example.com",
      avatar: "/placeholder.svg?height=40&width=40",
    },
    subject: "New Client Proposal",
    message: `Dear Alex,

I've drafted a proposal for the new client we discussed last week. The scope includes website redesign, SEO optimization, and a three-month social media campaign.

Based on their requirements and our initial discussions, I've estimated the project timeline to be approximately 12 weeks. The budget aligns with similar projects we've done in the past.

Please review the attached proposal and let me know if you'd like to make any changes before I send it to the client.

Regards,
Noah`,
    time: "Apr 28, 2:45 PM",
    labels: ["work", "project"],
    read: true,
    starred: true,
    important: true,
  },
];

// Utility functions
function getInitials(name: string) {
  return name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .toUpperCase()
    .substring(0, 2);
}

function formatFileSize(bytes: number) {
  if (bytes < 1024) return bytes + " B";
  else if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
  else return (bytes / 1048576).toFixed(1) + " MB";
}

function getFileIcon(type: string) {
  switch (type) {
    case "pdf":
      return FileText;
    case "xlsx":
    case "xls":
    case "csv":
      return FileText;
    case "jpg":
    case "jpeg":
    case "png":
    case "gif":
      return FileText;
    default:
      return File;
  }
}

// Additional components
function LogOutIcon(props: React.ComponentProps<typeof LucideUser>) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" y1="12" x2="9" y2="12" />
    </svg>
  );
}

function RefreshCwIcon(props: React.ComponentProps<typeof LucideUser>) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8" />
      <path d="M21 3v5h-5" />
      <path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16" />
      <path d="M3 21v-5h5" />
    </svg>
  );
}

function DownloadIcon(props: React.ComponentProps<typeof LucideUser>) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" x2="12" y1="15" y2="3" />
    </svg>
  );
}

// Main component - exported as a named export instead of default export
export function GmailApp() {
  // State
  const [selectedFolder, setSelectedFolder] = useState<string>("inbox");
  const [selectedEmail, setSelectedEmail] = useState<Email | null>(null);
  const [selectedEmails, setSelectedEmails] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [isComposeOpen, setIsComposeOpen] = useState(false);
  const [composeData, setComposeData] = useState({
    to: "",
    subject: "",
    message: "",
  });
  const [isCommandOpen, setIsCommandOpen] = useState(false);
  const [defaultLayout, setDefaultLayout] = useState([265, 440, 655]);
  const [isCollapsed, setIsCollapsed] = useState(false);

  // Effect to handle keyboard shortcuts
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setIsCommandOpen((open) => !open);
      }
    };

    document.addEventListener("keydown", down);
    return () => document.removeEventListener("keydown", down);
  }, []);

  // Filter emails based on selected folder and search query
  const filteredEmails = emails.filter((email) => {
    const matchesSearch =
      searchQuery === "" ||
      email.subject.toLowerCase().includes(searchQuery.toLowerCase()) ||
      email.from.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      email.message.toLowerCase().includes(searchQuery.toLowerCase());

    if (selectedFolder === "inbox") return matchesSearch;
    if (selectedFolder === "starred") return email.starred && matchesSearch;
    if (selectedFolder === "important") return email.important && matchesSearch;
    if (selectedFolder === "sent") return false; // For demo purposes
    if (selectedFolder === "drafts") return false; // For demo purposes
    if (selectedFolder === "trash") return false; // For demo purposes
    if (selectedFolder === "archive") return false; // For demo purposes

    // Categories
    if (selectedFolder === "social")
      return email.labels.includes("personal") && matchesSearch;
    if (selectedFolder === "updates")
      return email.labels.includes("work") && matchesSearch;
    if (selectedFolder === "forums")
      return email.labels.includes("project") && matchesSearch;
    if (selectedFolder === "promotions")
      return email.labels.includes("finance") && matchesSearch;
    if (selectedFolder === "shopping")
      return email.labels.includes("travel") && matchesSearch;

    return matchesSearch;
  });

  const getLabelColor = (labelId: string) => {
    const label = labels.find((l) => l.id === labelId);
    return label?.color || "bg-gray-500";
  };

  const handleSelectAllEmails = () => {
    if (selectedEmails.length === filteredEmails.length) {
      setSelectedEmails([]);
    } else {
      setSelectedEmails(filteredEmails.map((email) => email.id));
    }
  };

  const handleSelectEmail = (emailId: string) => {
    if (selectedEmails.includes(emailId)) {
      setSelectedEmails(selectedEmails.filter((id) => id !== emailId));
    } else {
      setSelectedEmails([...selectedEmails, emailId]);
    }
  };

  const handleStarEmail = (emailId: string, event: React.MouseEvent) => {
    event.stopPropagation();
    // In a real app, you would update the email in the database
    console.log("Star email:", emailId);
  };

  const handleDeleteEmails = () => {
    // In a real app, you would delete the emails from the database
    console.log("Delete emails:", selectedEmails);
    setSelectedEmails([]);
  };

  const handleArchiveEmails = () => {
    // In a real app, you would archive the emails
    console.log("Archive emails:", selectedEmails);
    setSelectedEmails([]);
  };

  const handleMarkAsRead = () => {
    // In a real app, you would mark the emails as read
    console.log("Mark as read:", selectedEmails);
    setSelectedEmails([]);
  };

  const handleMarkAsUnread = () => {
    // In a real app, you would mark the emails as unread
    console.log("Mark as unread:", selectedEmails);
    setSelectedEmails([]);
  };

  const handleReply = (email: Email) => {
    setComposeData({
      to: email.from.email,
      subject: `Re: ${email.subject}`,
      message: `\n\n-------- Original Message --------\nFrom: ${email.from.name} <${email.from.email}>\nDate: ${email.time}\nSubject: ${email.subject}\n\n${email.message}`,
    });
    setIsComposeOpen(true);
  };

  const handleForward = (email: Email) => {
    setComposeData({
      to: "",
      subject: `Fwd: ${email.subject}`,
      message: `\n\n-------- Forwarded Message --------\nFrom: ${email.from.name} <${email.from.email}>\nDate: ${email.time}\nSubject: ${email.subject}\n\n${email.message}`,
    });
    setIsComposeOpen(true);
  };

  const handleCompose = () => {
    setComposeData({
      to: "",
      subject: "",
      message: "",
    });
    setIsComposeOpen(true);
  };

  const handleSendEmail = () => {
    // In a real app, you would send the email
    console.log("Send email:", composeData);
    setIsComposeOpen(false);
  };

  // Update the color scheme and styling to match Gmail's design
  // Replace the sidebar implementation with Gmail's style
  // Change the header to match Gmail's header
  // Update the compose button to be a prominent rounded button
  // Modify the email list view to be more compact and Gmail-like

  // In the GmailApp component, replace the return statement with this updated UI:

  return (
    <TooltipProvider>
      <div className="flex h-screen w-full flex-col overflow-hidden bg-white">
        {/* Header - Gmail style */}
        <header className="flex h-16 items-center gap-4 border-b border-gray-200 bg-white px-4 lg:px-6">
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className="h-10 w-10 rounded-full text-gray-500 hover:bg-gray-100 lg:hidden"
            >
              <Menu className="h-5 w-5" />
              <span className="sr-only">Menu</span>
            </Button>
            <div className="flex items-center">
              <svg
                viewBox="0 0 75 24"
                width="75"
                height="24"
                xmlns="http://www.w3.org/2000/svg"
                aria-hidden="true"
                className="h-[24px] w-[75px]"
              >
                <g id="qaEJec">
                  <path
                    fill="#ea4335"
                    d="M67.954 16.303c-1.33 0-2.278-.608-2.886-1.804l7.967-3.3-.27-.68c-.495-1.33-2.008-3.79-5.102-3.79-3.068 0-5.622 2.41-5.622 5.96 0 3.34 2.53 5.96 5.92 5.96 2.73 0 4.31-1.67 4.97-2.64l-2.03-1.35c-.673.98-1.6 1.64-2.93 1.64zm-.203-7.27c1.04 0 1.92.52 2.21 1.264l-5.32 2.21c-.06-2.3 1.79-3.474 3.12-3.474z"
                  ></path>
                </g>
                <g id="YGlOvc">
                  <path
                    fill="#34a853"
                    d="M58.193.67h2.564v17.44h-2.564z"
                  ></path>
                </g>
                <g id="BWfIk">
                  <path
                    fill="#4285f4"
                    d="M54.152 8.066h-.088c-.588-.697-1.716-1.33-3.136-1.33-2.98 0-5.71 2.614-5.71 5.98 0 3.338 2.73 5.933 5.71 5.933 1.42 0 2.548-.64 3.136-1.36h.088v.86c0 2.28-1.217 3.5-3.183 3.5-1.61 0-2.6-1.15-3-2.12l-2.28.94c.65 1.58 2.39 3.52 5.28 3.52 3.06 0 5.66-1.807 5.66-6.206V7.21h-2.48v.858zm-3.006 8.237c-1.804 0-3.318-1.513-3.318-3.588 0-2.1 1.514-3.635 3.318-3.635 1.784 0 3.183 1.534 3.183 3.635 0 2.075-1.4 3.588-3.19 3.588z"
                  ></path>
                </g>
                <g id="e6m3fd">
                  <path
                    fill="#fbbc05"
                    d="M38.17 6.735c-3.28 0-5.953 2.506-5.953 5.96 0 3.432 2.673 5.96 5.954 5.96 3.29 0 5.96-2.528 5.96-5.96 0-3.46-2.67-5.96-5.95-5.96zm0 9.568c-1.798 0-3.348-1.487-3.348-3.61 0-2.14 1.55-3.608 3.35-3.608s3.348 1.467 3.348 3.61c0 2.116-1.55 3.608-3.35 3.608z"
                  ></path>
                </g>
                <g id="vbkDmc">
                  <path
                    fill="#ea4335"
                    d="M25.17 6.71c-3.28 0-5.954 2.505-5.954 5.958 0 3.433 2.673 5.96 5.954 5.96 3.282 0 5.955-2.527 5.955-5.96 0-3.453-2.673-5.96-5.955-5.96zm0 9.567c-1.8 0-3.35-1.487-3.35-3.61 0-2.14 1.55-3.608 3.35-3.608s3.35 1.46 3.35 3.6c0 2.12-1.55 3.61-3.35 3.61z"
                  ></path>
                </g>
                <g id="idEJde">
                  <path
                    fill="#4285f4"
                    d="M14.11 14.182c.722-.723 1.205-1.78 1.387-3.334H9.423V8.373h8.518c.09.452.16 1.07.16 1.664 0 1.903-.52 4.26-2.19 5.934-1.63 1.7-3.71 2.61-6.48 2.61-5.12 0-9.42-4.17-9.42-9.29C0 4.17 4.31 0 9.43 0c2.83 0 4.843 1.108 6.362 2.56L14 4.347c-1.087-1.02-2.56-1.81-4.577-1.81-3.74 0-6.662 3.01-6.662 6.75s2.93 6.75 6.67 6.75c2.43 0 3.81-.972 4.69-1.856z"
                  ></path>
                </g>
              </svg>
              <span className="ml-2 text-xl font-normal text-gray-600">
                Gmail
              </span>
            </div>
          </div>

          {/* Gmail search bar */}
          <div className="relative mx-4 flex-1 max-w-2xl">
            <div className="flex h-12 items-center rounded-lg bg-gray-100 px-4 hover:bg-white hover:shadow-md focus-within:bg-white focus-within:shadow-md">
              <Search className="mr-2 h-5 w-5 text-gray-500" />
              <Input
                placeholder="Search mail"
                className="h-full border-0 bg-transparent shadow-none focus-visible:ring-0 focus-visible:ring-offset-0"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
              <Button
                variant="ghost"
                size="icon"
                className="ml-auto h-8 w-8 text-gray-500"
              >
                <ListFilter className="h-5 w-5" />
              </Button>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-10 w-10 rounded-full text-gray-500 hover:bg-gray-100"
                >
                  <HelpCircle className="h-5 w-5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Support</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-10 w-10 rounded-full text-gray-500 hover:bg-gray-100"
                >
                  <Settings className="h-5 w-5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Settings</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-10 w-10 rounded-full text-gray-500 hover:bg-gray-100"
                >
                  <Grid className="h-5 w-5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Google apps</TooltipContent>
            </Tooltip>

            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="relative h-10 w-10 rounded-full"
                >
                  <Avatar className="h-9 w-9">
                    <AvatarImage
                      src={currentUser.avatar || "/placeholder.svg"}
                      alt={currentUser.name}
                    />
                    <AvatarFallback>
                      {getInitials(currentUser.name)}
                    </AvatarFallback>
                  </Avatar>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <div className="flex items-center justify-start gap-2 p-2">
                  <Avatar className="h-10 w-10">
                    <AvatarImage
                      src={currentUser.avatar || "/placeholder.svg"}
                      alt={currentUser.name}
                    />
                    <AvatarFallback>
                      {getInitials(currentUser.name)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex flex-col space-y-1 leading-none">
                    <p className="font-medium">{currentUser.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {currentUser.email}
                    </p>
                  </div>
                </div>
                <DropdownMenuSeparator />
                <DropdownMenuItem>
                  <LucideUser className="mr-2 h-4 w-4" />
                  <span>Manage your Google Account</span>
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem>
                  <LogOutIcon className="mr-2 h-4 w-4" />
                  <span>Sign out</span>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>

        <div className="flex flex-1 overflow-hidden">
          {/* Gmail-style sidebar */}
          <div
            className={cn(
              "flex w-64 flex-col bg-white transition-all duration-300 ease-in-out",
              isCollapsed && "w-20"
            )}
          >
            {/* Gmail's compose button */}
            <div className="p-4">
              <Button
                onClick={handleCompose}
                className="flex h-14 w-full items-center justify-start gap-3 rounded-2xl bg-[#c2e7ff] px-6 py-4 text-gray-800 hover:bg-[#b4deff] hover:shadow-md"
              >
                <PenLine className="h-5 w-5" />
                {!isCollapsed && <span className="font-medium">Compose</span>}
              </Button>
            </div>

            <ScrollArea className="flex-1">
              <div className="px-2 py-1">
                <div className="space-y-1">
                  {folders.map((folder) => (
                    <Button
                      key={folder.id}
                      variant="ghost"
                      className={cn(
                        "w-full justify-start rounded-r-full px-6 py-2 font-normal",
                        selectedFolder === folder.id
                          ? "bg-[#d3e3fd] font-medium text-[#041e49] hover:bg-[#d3e3fd]"
                          : "text-gray-700",
                        isCollapsed && "justify-center px-2"
                      )}
                      onClick={() => setSelectedFolder(folder.id)}
                    >
                      <folder.icon
                        className={cn(
                          "h-5 w-5",
                          selectedFolder === folder.id
                            ? "text-[#041e49]"
                            : "text-gray-700"
                        )}
                      />
                      {!isCollapsed && (
                        <>
                          <span className="ml-4">{folder.name}</span>
                          {folder.count !== undefined && (
                            <span
                              className={cn(
                                "ml-auto text-sm",
                                selectedFolder === folder.id
                                  ? "text-[#041e49]"
                                  : "text-gray-500"
                              )}
                            >
                              {folder.count}
                            </span>
                          )}
                        </>
                      )}
                    </Button>
                  ))}
                </div>

                <Separator className="my-3 bg-gray-200" />

                <div className="space-y-1">
                  <h3
                    className={cn(
                      "mb-1 px-6 text-sm font-medium text-gray-500",
                      isCollapsed && "sr-only"
                    )}
                  >
                    Categories
                  </h3>
                  {categories.map((category) => (
                    <Button
                      key={category.id}
                      variant="ghost"
                      className={cn(
                        "w-full justify-start rounded-r-full px-6 py-2 font-normal",
                        selectedFolder === category.id
                          ? "bg-[#d3e3fd] font-medium text-[#041e49] hover:bg-[#d3e3fd]"
                          : "text-gray-700",
                        isCollapsed && "justify-center px-2"
                      )}
                      onClick={() => setSelectedFolder(category.id)}
                    >
                      <category.icon
                        className={cn(
                          "h-5 w-5",
                          selectedFolder === category.id
                            ? "text-[#041e49]"
                            : "text-gray-700"
                        )}
                      />
                      {!isCollapsed && (
                        <>
                          <span className="ml-4">{category.name}</span>
                          {category.count !== undefined && (
                            <span
                              className={cn(
                                "ml-auto text-sm",
                                selectedFolder === category.id
                                  ? "text-[#041e49]"
                                  : "text-gray-500"
                              )}
                            >
                              {category.count}
                            </span>
                          )}
                        </>
                      )}
                    </Button>
                  ))}
                </div>

                <Separator className="my-3 bg-gray-200" />

                <div className="space-y-1">
                  <div className="flex items-center justify-between px-6">
                    <h3
                      className={cn(
                        "text-sm font-medium text-gray-500",
                        isCollapsed && "sr-only"
                      )}
                    >
                      Labels
                    </h3>
                    {!isCollapsed && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-5 w-5 text-gray-500"
                      >
                        <Plus className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                  {labels.map((label) => (
                    <Button
                      key={label.id}
                      variant="ghost"
                      className={cn(
                        "w-full justify-start rounded-r-full px-6 py-2 font-normal text-gray-700",
                        isCollapsed && "justify-center px-2"
                      )}
                    >
                      <div className={`h-3 w-3 rounded-full ${label.color}`} />
                      {!isCollapsed && (
                        <span className="ml-4">{label.name}</span>
                      )}
                    </Button>
                  ))}
                </div>
              </div>
            </ScrollArea>

            <div className="p-2">
              <Button
                variant="ghost"
                size="icon"
                className="h-10 w-10 rounded-full text-gray-500"
                onClick={() => setIsCollapsed(!isCollapsed)}
              >
                {isCollapsed ? (
                  <ChevronRight className="h-5 w-5" />
                ) : (
                  <ChevronLeft className="h-5 w-5" />
                )}
              </Button>
            </div>
          </div>

          {/* Main content with resizable panels */}
          <div className="flex flex-1 flex-col">
            {/* Email list toolbar */}
            <div className="flex items-center border-b border-gray-200 px-4 py-2">
              <div className="flex items-center gap-2">
                <Checkbox
                  checked={
                    selectedEmails.length > 0 &&
                    selectedEmails.length === filteredEmails.length
                  }
                  onCheckedChange={handleSelectAllEmails}
                  className="h-4 w-4 rounded-sm border-gray-400"
                  aria-label="Select all"
                />
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 rounded-full text-gray-500"
                >
                  <RefreshCwIcon className="h-4 w-4" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-8 w-8 rounded-full text-gray-500"
                >
                  <MoreVertical className="h-4 w-4" />
                </Button>
              </div>

              {selectedEmails.length > 0 ? (
                <div className="ml-4 flex items-center gap-2">
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                    onClick={handleArchiveEmails}
                  >
                    <Archive className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                    onClick={handleDeleteEmails}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                    onClick={handleMarkAsRead}
                  >
                    <MailOpen className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                    onClick={handleMarkAsUnread}
                  >
                    <MailX className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                  >
                    <Clock className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                  >
                    <FolderPlus className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 rounded-full text-gray-500"
                  >
                    <Tag className="h-4 w-4" />
                  </Button>
                </div>
              ) : (
                <div className="ml-auto flex items-center gap-2">
                  <Tabs defaultValue="primary" className="w-auto">
                    <TabsList className="h-9 bg-transparent p-0">
                      <TabsTrigger
                        value="primary"
                        className="h-9 rounded-none border-b-2 border-transparent px-3 py-0 data-[state=active]:border-blue-500 data-[state=active]:bg-transparent data-[state=active]:shadow-none"
                      >
                        Primary
                      </TabsTrigger>
                      <TabsTrigger
                        value="social"
                        className="h-9 rounded-none border-b-2 border-transparent px-3 py-0 data-[state=active]:border-blue-500 data-[state=active]:bg-transparent data-[state=active]:shadow-none"
                      >
                        Social
                      </TabsTrigger>
                      <TabsTrigger
                        value="promotions"
                        className="h-9 rounded-none border-b-2 border-transparent px-3 py-0 data-[state=active]:border-blue-500 data-[state=active]:bg-transparent data-[state=active]:shadow-none"
                      >
                        Promotions
                      </TabsTrigger>
                      <TabsTrigger
                        value="updates"
                        className="h-9 rounded-none border-b-2 border-transparent px-3 py-0 data-[state=active]:border-blue-500 data-[state=active]:bg-transparent data-[state=active]:shadow-none"
                      >
                        Updates
                      </TabsTrigger>
                    </TabsList>
                  </Tabs>
                </div>
              )}
            </div>

            {/* Email list */}
            <ScrollArea className="flex-1">
              <div className="divide-y divide-gray-100">
                {filteredEmails.length > 0 ? (
                  filteredEmails.map((email) => (
                    <ContextMenu key={email.id}>
                      <ContextMenuTrigger asChild>
                        <div
                          className={cn(
                            "flex cursor-pointer items-center gap-3 px-4 py-2 hover:shadow-md",
                            !email.read && "bg-[#f2f6fc]",
                            selectedEmail?.id === email.id && "bg-[#c2dbff]",
                            selectedEmails.includes(email.id) && "bg-[#c2dbff]"
                          )}
                          onClick={() => setSelectedEmail(email)}
                        >
                          <div className="flex items-center gap-3">
                            <Checkbox
                              checked={selectedEmails.includes(email.id)}
                              onCheckedChange={() =>
                                handleSelectEmail(email.id)
                              }
                              onClick={(e) => e.stopPropagation()}
                              className="h-4 w-4 rounded-sm border-gray-400"
                            />
                            <Button
                              variant="ghost"
                              size="icon"
                              className={cn(
                                "h-6 w-6 rounded-full p-0",
                                email.starred && "text-amber-500"
                              )}
                              onClick={(e) => handleStarEmail(email.id, e)}
                            >
                              <Star
                                className={cn(
                                  "h-4 w-4",
                                  email.starred && "fill-amber-500"
                                )}
                              />
                              <span className="sr-only">Star</span>
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              className={cn(
                                "h-6 w-6 rounded-full p-0",
                                email.important && "text-amber-500"
                              )}
                              onClick={(e) => {
                                e.stopPropagation();
                                // Toggle important flag
                              }}
                            >
                              <MailQuestion
                                className={cn(
                                  "h-4 w-4",
                                  email.important && "fill-amber-500"
                                )}
                              />
                              <span className="sr-only">Important</span>
                            </Button>
                          </div>

                          <div className="flex flex-1 items-center gap-3 overflow-hidden py-1">
                            <div className="w-44 flex-shrink-0 truncate font-medium">
                              {email.from.name}
                            </div>
                            <div className="flex flex-1 items-center gap-2 overflow-hidden">
                              <span
                                className={cn(
                                  "truncate",
                                  !email.read && "font-bold"
                                )}
                              >
                                {email.subject}
                              </span>
                              <span className="truncate text-sm text-gray-500">
                                - {email.message.split("\n")[0]}
                              </span>
                            </div>
                            <div className="ml-auto flex items-center gap-2">
                              {email.labels.length > 0 && (
                                <div className="flex gap-1">
                                  {email.labels.slice(0, 2).map((labelId) => {
                                    const label = labels.find(
                                      (l) => l.id === labelId
                                    );
                                    return (
                                      <div
                                        key={labelId}
                                        className={`h-2 w-2 rounded-full ${
                                          label?.color || "bg-gray-400"
                                        }`}
                                      />
                                    );
                                  })}
                                </div>
                              )}
                              {email.attachments &&
                                email.attachments.length > 0 && (
                                  <Paperclip className="h-4 w-4 text-gray-400" />
                                )}
                              <span className="whitespace-nowrap text-xs text-gray-500">
                                {email.time}
                              </span>
                            </div>
                          </div>
                        </div>
                      </ContextMenuTrigger>
                      <ContextMenuContent>
                        <ContextMenuItem
                          onClick={() => setSelectedEmail(email)}
                        >
                          <MailOpen className="mr-2 h-4 w-4" />
                          <span>Open</span>
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => handleReply(email)}>
                          <Reply className="mr-2 h-4 w-4" />
                          <span>Reply</span>
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => handleForward(email)}>
                          <Forward className="mr-2 h-4 w-4" />
                          <span>Forward</span>
                        </ContextMenuItem>
                        <ContextMenuSeparator />
                        <ContextMenuItem
                          onClick={() =>
                            handleStarEmail(email.id, {} as React.MouseEvent)
                          }
                        >
                          <Star className="mr-2 h-4 w-4" />
                          <span>{email.starred ? "Unstar" : "Star"}</span>
                        </ContextMenuItem>
                        <ContextMenuItem
                          onClick={() => handleSelectEmail(email.id)}
                        >
                          <Check className="mr-2 h-4 w-4" />
                          <span>
                            {selectedEmails.includes(email.id)
                              ? "Deselect"
                              : "Select"}
                          </span>
                        </ContextMenuItem>
                        <ContextMenuSeparator />
                        <ContextMenuItem
                          onClick={() => {
                            setSelectedEmails([email.id]);
                            handleArchiveEmails();
                          }}
                        >
                          <Archive className="mr-2 h-4 w-4" />
                          <span>Archive</span>
                        </ContextMenuItem>
                        <ContextMenuItem
                          onClick={() => {
                            setSelectedEmails([email.id]);
                            handleDeleteEmails();
                          }}
                          className="text-red-600"
                        >
                          <Trash2 className="mr-2 h-4 w-4" />
                          <span>Delete</span>
                        </ContextMenuItem>
                      </ContextMenuContent>
                    </ContextMenu>
                  ))
                ) : (
                  <div className="flex flex-col items-center justify-center py-12">
                    <div className="rounded-full bg-gray-100 p-3">
                      <Inbox className="h-6 w-6 text-gray-400" />
                    </div>
                    <h3 className="mt-4 text-lg font-medium">
                      No emails found
                    </h3>
                    <p className="mt-2 text-center text-sm text-gray-500">
                      {searchQuery
                        ? "Try a different search term"
                        : "Your inbox is empty"}
                    </p>
                  </div>
                )}
              </div>
            </ScrollArea>

            {/* Email content panel - only shown when an email is selected */}
            {selectedEmail && (
              <div className="absolute inset-0 z-10 flex flex-col bg-white">
                <div className="flex items-center justify-between border-b border-gray-200 px-4 py-2">
                  <div className="flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                      onClick={() => setSelectedEmail(null)}
                    >
                      <ArrowLeft className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                      onClick={handleArchiveEmails}
                    >
                      <Archive className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                      onClick={handleDeleteEmails}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                      onClick={handleMarkAsUnread}
                    >
                      <MailX className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                    >
                      <Clock className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                    >
                      <FolderPlus className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                    >
                      <Tag className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 rounded-full text-gray-500"
                    >
                      <MoreVertical className="h-4 w-4" />
                    </Button>
                  </div>
                  <div className="flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-xs text-gray-500"
                    >
                      <ChevronLeft className="mr-1 h-4 w-4" />
                      Newer
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-xs text-gray-500"
                    >
                      Older
                      <ChevronRight className="ml-1 h-4 w-4" />
                    </Button>
                  </div>
                </div>
                <ScrollArea className="flex-1">
                  <div className="p-6">
                    <div className="mb-6">
                      <h1 className="text-2xl font-normal text-gray-800">
                        {selectedEmail.subject}
                      </h1>
                      <div className="mt-4 flex items-start justify-between">
                        <div className="flex items-start gap-3">
                          <Avatar className="h-10 w-10">
                            <AvatarImage
                              src={
                                selectedEmail.from.avatar || "/placeholder.svg"
                              }
                              alt={selectedEmail.from.name}
                            />
                            <AvatarFallback>
                              {getInitials(selectedEmail.from.name)}
                            </AvatarFallback>
                          </Avatar>
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="font-medium">
                                {selectedEmail.from.name}
                              </span>
                              <span className="text-xs text-gray-500">
                                &lt;{selectedEmail.from.email}&gt;
                              </span>
                            </div>
                            <div className="mt-1 flex items-center gap-2 text-xs text-gray-500">
                              <span>to me</span>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-4 w-4 p-0 text-gray-400"
                              >
                                <ChevronDown className="h-3 w-3" />
                              </Button>
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-gray-500">
                            {selectedEmail.time}
                          </span>
                          <Button
                            variant="ghost"
                            size="icon"
                            className={cn(
                              "h-8 w-8 rounded-full",
                              selectedEmail.starred && "text-amber-500"
                            )}
                            onClick={(e) =>
                              handleStarEmail(selectedEmail.id, e)
                            }
                          >
                            <Star
                              className={cn(
                                "h-4 w-4",
                                selectedEmail.starred && "fill-amber-500"
                              )}
                            />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 rounded-full text-gray-500"
                          >
                            <Reply className="h-4 w-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 rounded-full text-gray-500"
                          >
                            <MoreVertical className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    </div>
                    <div className="prose prose-sm max-w-none">
                      {selectedEmail.message.split("\n").map((paragraph, i) => (
                        <p key={i}>{paragraph}</p>
                      ))}
                    </div>
                    {selectedEmail.attachments &&
                      selectedEmail.attachments.length > 0 && (
                        <div className="mt-6 border-t border-gray-200 pt-4">
                          <h3 className="mb-2 text-sm font-medium">
                            Attachments
                          </h3>
                          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                            {selectedEmail.attachments.map((attachment) => {
                              const FileIcon = getFileIcon(attachment.type);
                              return (
                                <Card
                                  key={attachment.id}
                                  className="overflow-hidden border border-gray-200"
                                >
                                  <CardHeader className="flex flex-row items-center gap-2 space-y-0 p-3">
                                    <FileIcon className="h-4 w-4 text-gray-500" />
                                    <div className="flex-1 truncate text-sm font-medium">
                                      {attachment.name}
                                    </div>
                                    <div className="text-xs text-gray-500">
                                      {attachment.size}
                                    </div>
                                  </CardHeader>
                                  <CardContent className="p-0">
                                    {attachment.type === "jpg" ||
                                    attachment.type === "jpeg" ||
                                    attachment.type === "png" ||
                                    attachment.type === "gif" ? (
                                      <div className="aspect-video bg-gray-100">
                                        <img
                                          src="/placeholder.svg?height=200&width=400"
                                          alt={attachment.name}
                                          className="h-full w-full object-cover"
                                        />
                                      </div>
                                    ) : null}
                                  </CardContent>
                                  <CardFooter className="p-2">
                                    <Button
                                      variant="ghost"
                                      size="sm"
                                      className="h-7 w-full gap-1 text-xs"
                                    >
                                      <DownloadIcon className="h-3 w-3" />
                                      <span>Download</span>
                                    </Button>
                                  </CardFooter>
                                </Card>
                              );
                            })}
                          </div>
                        </div>
                      )}
                    <div className="mt-6 flex gap-2">
                      <Button className="gap-2 bg-[#0b57d0] text-white hover:bg-[#0842a0]">
                        <Reply className="h-4 w-4" />
                        Reply
                      </Button>
                      <Button
                        variant="outline"
                        className="gap-2 border-gray-300 text-gray-700"
                      >
                        <Forward className="h-4 w-4" />
                        Forward
                      </Button>
                    </div>
                  </div>
                </ScrollArea>
              </div>
            )}
          </div>
        </div>

        {/* Command menu */}

        {/* Compose email dialog */}
      </div>
    </TooltipProvider>
  );
}

// Missing Menu icon component
function Menu(props: React.ComponentProps<typeof LucideUser>) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <line x1="4" x2="20" y1="12" y2="12" />
      <line x1="4" x2="20" y1="6" y2="6" />
      <line x1="4" x2="20" y1="18" y2="18" />
    </svg>
  );
}
