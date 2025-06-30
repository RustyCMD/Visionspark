<div align="center">
  <img src="visionspark/assets/logo.png" alt="Visionspark Logo" width="150"/>
  <h1>Visionspark</h1>
  <p>✨ AI-Powered Image Generation & Gallery 🎨</p>
</div>

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Supabase-3FCF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=for-the-badge" alt="Contributions Welcome">
</div>

Welcome to Visionspark, a cutting-edge cross-platform application built with Flutter and powered by a robust Supabase backend. Visionspark offers a seamless and intuitive experience for generating stunning AI-driven images and exploring a vibrant community gallery.

---

## 📜 Table of Contents

- [🌟 Features at a Glance](#-features-at-a-glance)
- [📸 App Showcase](#-app-showcase)
- [🏗️ Project Architecture](#️-project-architecture)
- [🚀 Getting Started](#-getting-started)
- [🛠️ Supabase Backend Deep Dive](#️-supabase-backend-deep-dive)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)

---

## 🌟 Features at a Glance

-   👤 **User Management**: Secure authentication (sign-up, login, password reset), comprehensive account management including username updates, profile pictures, and join date tracking.
-   🤖 **AI Image Generation**: Unleash creativity with advanced AI models (DALL-E 3 via Supabase Edge Functions), get intelligent prompt suggestions, and manage daily generation limits tracked by user timezone.
-   🖼️ **Dynamic Image Gallery**: Explore a public showcase of AI-generated masterpieces, view your own creations, and engage with content through likes. Features optimized loading and easy image downloads.
-   ⚙️ **Customizable Settings**: Seamlessly switch between Dark and Light themes and toggle auto-upload for generated images.
-   💳 **Subscription Framework**: Integrated UI for exploring and selecting in-app purchase subscriptions.
-   🆘 **Dedicated Support System**: In-app reporting for support issues via a Discord webhook with robust, database-backed rate limiting.
-   📱 **Cross-Platform Excellence**: A consistent experience across Android, iOS, and future platforms, built with Flutter.
-   🌐 **Offline Resilience**: A user-friendly offline screen with a retry option ensures a smooth experience without an internet connection.

---

## 📸 App Showcase

*(Add your screenshots here to showcase the app's beautiful UI!)*

| Auth Screen                                     | Image Generator                               | Gallery                                       |
| ----------------------------------------------- | --------------------------------------------- | --------------------------------------------- |
| ![Auth Screen](link-to-your-screenshot.png)     | ![Generator](link-to-your-screenshot.png)     | ![Gallery](link-to-your-screenshot.png)       |

---

## 🏗️ Project Architecture

Visionspark's codebase is thoughtfully organized into the Flutter front-end and the Supabase back-end.

```
Visionspark/
├── visionspark/           # Main Flutter app source code
│   ├── lib/               # Dart source code
│   ├── android/           # Native Android code
│   ├── ios/               # Native iOS code
│   └── pubspec.yaml       # Dependencies
├── supabase/              # Supabase backend resources
│   ├── functions/         # Edge Functions (serverless logic)
│   ├── migrations/        # SQL migration scripts
│   └── config.toml        # Supabase CLI configuration
├── .cursor/               # Cursor navigation rules
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

### 📱 `visionspark/lib` (Flutter/Dart Files)

This directory houses the core Flutter application logic and UI components, structured for modularity:

-   `auth/`: Screens and logic for user authentication.
-   `features/`: Distinct feature modules (account, gallery, image_generator, etc.).
-   `shared/`: Common widgets, utilities, and services.
-   `main.dart`: The application's entry point.

### 🚀 `supabase/` (Supabase Backend)

This folder contains all files to manage the Supabase backend:

-   `functions/`: TypeScript Edge Functions for server-side operations like AI image generation, account deletion, and gallery feeds.
-   `migrations/`: Version-controlled SQL scripts that define and evolve the database schema.
-   `config.toml`: Configuration for the Supabase CLI.
-   `SECURITY_GUIDANCE.md`: Important security best practices.

---

## 🚀 Getting Started

Follow these steps to set up and run Visionspark locally.

### Prerequisites

-   **Flutter SDK**: Latest stable release recommended.
-   **Dart SDK**: Bundled with Flutter.
-   **Supabase CLI**: For managing the backend.
-   **Node.js & npm**: For Supabase Edge Functions development.
-   An active **Supabase account**.

### Setup Guide

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/RustyCMD/Visionspark.git
    cd Visionspark
    ```

2.  **Set up Your Supabase Project**:
    -   Create a new project on [Supabase.com](https://supabase.com).
    -   Retrieve your **Project URL** and **Anon Key**.
    -   Configure these **Environment Variables** in your Supabase project dashboard (Project Settings > Edge Functions):
        -   `SUPABASE_SERVICE_ROLE_KEY`: Found in your project's API Settings.
        -   `OPENAI_API_KEY`: Your OpenAI API key.
        -   `DISCORD_WEBHOOK`: Your Discord webhook URL for support messages.

3.  **Configure the Flutter Application**:
    -   Navigate to the Flutter app directory:
        ```bash
        cd visionspark
        ```
    -   Create a `.env` file (`visionspark/.env`) and add your credentials:
        ```
        SUPABASE_URL=YOUR_SUPABASE_PROJECT_URL
        SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
        ```
    -   **Security Note**: Ensure `.env` is listed in your root `.gitignore`.

4.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

5.  **Set up Local Supabase Environment**:
    -   Navigate to the Supabase directory:
        ```bash
        cd ../supabase
        ```
    -   Log in and link your project:
        ```bash
        supabase login
        supabase link --project-ref YOUR_PROJECT_REF
        ```
    -   To run services locally:
        ```bash
        supabase start
        ```

6.  **Deploy Supabase Migrations & Functions**:
    -   Push database migrations:
        ```bash
        supabase db push
        ```
    -   Deploy Edge Functions:
        ```bash
        # Deploy specific functions
        supabase functions deploy --project-ref YOUR_PROJECT_REF [FUNCTION_NAME]

        # Or deploy all functions
        supabase functions deploy --project-ref YOUR_PROJECT_REF --all
        ```

7.  **Run the Flutter App**:
    -   Return to the Flutter app directory:
        ```bash
        cd ../visionspark
        ```
    -   Launch the app:
        ```bash
        flutter run
        ```

---

## 🛠️ Supabase Backend Deep Dive

The Supabase backend powers Visionspark's data, authentication, and serverless logic.

-   **Edge Functions**: Low-latency TypeScript functions handling critical operations. Ensure all required environment variables (`SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`, `DISCORD_WEBHOOK`) are correctly set.
-   **Database Migrations**: Version-controlled SQL scripts in `supabase/migrations/` define the database schema, including tables, triggers, and functions to maintain data integrity.

---

## 🤝 Contributing

We warmly welcome contributions to Visionspark! If you're interested in improving the app or adding new features, please follow these guidelines:

1.  **Fork** the repository.
2.  Create a new feature branch: `git checkout -b feature/your-awesome-feature`.
3.  Implement your changes and ensure tests pass.
4.  Commit your changes with a clear message: `git commit -m 'Feat: Add a new awesome feature'`.
5.  Push to your branch and open a **Pull Request**.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---
<div align="center">
  <p>Made with ❤️ and a bit of ✨</p>
</div>
