type ChatMessage = {
  date: string;
  sender: string;
  body: string;
  quote: string;
  sticker: string;
  reactions: string[];
  attachments: string[];
};

const path = "./signal-chats/ies/data.json";
const text = await Bun.file(path).text();

const messages: ChatMessage[] = [];
const errors: { line: number; message: string; raw: string }[] = [];

text.split(/\r?\n/).forEach((raw, idx) => {
  const line = raw.trim();
  const lineNo = idx + 1;

  // Skip blanks and `//`-prefixed comment lines
  if (!line || line.startsWith("//")) return;

  try {
    const obj = JSON.parse(line) as ChatMessage;
    messages.push(obj);
  } catch (e) {
    errors.push({
      line: lineNo,
      message: (e as Error).message,
      raw: raw.slice(0, 200),
    });
  }
});

console.log(`Parsed ${messages.length} messages`);

console.log(messages);

// Use `messages` from here on
