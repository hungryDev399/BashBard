

# BashBard

**BashBard** is your AI-powered Linux shell tutor and command storyteller. Whether you mistype a command or only know what you _want_ to do in plain English, BashBard crafts the perfect shell incantation—and explains why it works.



## Features

- **Auto-correction & Explanation**  
  If you type `sl`, BashBard suggests `ls -l`, explains the `-l` flag, and helps you learn as you go.

- **Natural-Language → Shell**  
  Describe your goal—“find all `.conf` files in `/etc` larger than 1 MB”—and receive the exact `find` command with annotations.

- **Context-Aware Guidance**  
  BashBard remembers your session history and current directory, so every suggestion is relevant to _where_ you are and _what_ you’ve done.
  
- **Safe-Mode Confirmations**  
  Dangerous operations (e.g. `rm -rf /`) trigger a “Type **YES** to proceed” prompt to prevent accidents.




## Installation

1. **Clone the repo**  
   ```bash
   git clone https://github.com/5afagy/BashBard.git
   cd bashbard
   pip install -r requirements.txt

2. **Configure your API keys**
   Open `.env` then add Gemini key:

   ```dotenv
   GEMINI_API_KEY=key.......
   ```

4. **Run BashBard**

   ```bash
   python shell.py
   ```



##  Usage Examples
<img width="1037" height="103" alt="image" src="https://github.com/user-attachments/assets/0f0c02b5-916f-4217-bf6e-4fa16777355f" />


````bash
BashBard> sl
Error: 'sl' is not recognized.
🤖 BashBard ▶️

 1 The user intended to run ls.
 2 ls
 3 The user likely mistyped ls (list directory contents), typing sl instead.
````

• You likely meant ‘list files in long format.’ The `-l` flag shows permissions, owners, and sizes.
```bash
BashBard> find logs --size +10M
find logs -size +10M
The option --size is not valid for find; the correct option is -size.
```



## 🤝 Contributing

1. Fork the repository  
2. Create a branch (`git checkout -b feature/xyz`)  
3. Commit your changes (`git commit -m 'Add feature'`)  
4. Push (`git push origin feature/xyz`) and open a Pull Request

Please keep AI system prompts in `ai_client.py` clear and concise.



## 📄 License

MIT © 2025 Khafagy



> Built with ❤️ by Khafagy  
> LinkedIn: [linkedin.com/in/khafagy](https://linkedin.com/in/khafagy)  
> Email: Ali5afagy@gmail.com  

