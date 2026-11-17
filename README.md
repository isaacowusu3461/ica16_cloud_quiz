
# ICA16 Cloud Quiz — Variant A

**Student:** Isaac Owusu  
**Course:** CSC 6360 — Mobile Application Development  
**Track:** Graduate  
**Framework:** Flutter  
**Backend:** Firebase Authentication and Cloud Firestore  
**Quiz API:** Open Trivia Database (OpenTDB)

## Project Overview

For this assignment, I developed a Flutter quiz application that retrieves questions from the Open Trivia Database API and saves completed quiz attempts to Firebase Cloud Firestore.

The application uses Firebase Authentication to identify users and ensure that quiz attempts are saved under the correct account.

My assigned variant is Variant A, which uses 10 easy General Knowledge multiple-choice questions.

The main focus of this assignment was not just building the quiz interface. I also worked on handling API errors, validating question data, preventing duplicate submissions, recovering uncertain cloud saves, and protecting Firestore records.

## Technologies Used

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore
- Open Trivia Database API
- HTTP package
- HTML Unescape package

## Quiz Configuration

The application uses the following API endpoint:

```text
https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple
```

The quiz settings are:

- Category: General Knowledge
- Category ID: 9
- Difficulty: Easy
- Question count: 10
- Question type: Multiple choice
- Number of choices per question: 4

Each question has one correct answer and three incorrect answers.

The answers are shuffled before they are displayed to the user.

## Features Implemented

### 1. Firebase Authentication

Users sign in using their email address and password.

Firebase Authentication provides a unique user ID, which is used when saving and retrieving quiz attempts.

The application also checks whether the signed-in account has changed before applying asynchronous results.

### 2. Quiz Questions

The application retrieves 10 questions from OpenTDB.

Before displaying the questions, it checks that:

- The HTTP request was successful.
- The API response code is 0.
- Exactly 10 questions were returned.
- Each question belongs to the expected category.
- Each question has the expected difficulty and type.
- Each question contains three incorrect answers.
- The answer choices are valid and do not contain duplicates.

HTML entities in the questions and answers are decoded before display.

### 3. Quiz Interface

The application displays one question at a time.

Users select one answer from four choices. After an answer is selected, the application displays whether it was correct or incorrect.

The application keeps track of the score throughout the quiz.

After answering all 10 questions, users can review their answers and see their final score.

### 4. Firestore Submission

After completing the quiz, users can submit their results to Cloud Firestore.

Each quiz round receives a unique round ID when the round begins.

The round ID remains the same during submission retries and recovery attempts.

The Firestore document path is:

```text
users/{uid}/attempts/{roundId}
```

Each attempt contains exactly six fields:

```text
schemaVersion
variant
categoryId
questionCount
correctCount
submittedAt
```

The values are:

```text
schemaVersion: 1
variant: A
categoryId: 9
questionCount: 10
correctCount: Final quiz score
submittedAt: Firestore server timestamp
```

The application uses a Firestore transaction to check whether the attempt already exists before creating a new document.

If an attempt with the same round ID already exists, the application checks whether its data matches the current submission.

A different score under the same round ID is treated as a collision.

### 5. Server Verification

The application does not treat a local write or a successful transaction response alone as proof that the attempt is saved.

It reads the attempt directly from the Firestore server and checks the saved fields.

The application displays "Cloud verified" only after the server confirms the expected document.

### 6. Offline Recovery

I implemented recovery for cases where the submission result is uncertain.

For example, a network interruption may happen after a write is attempted.

Instead of immediately creating another attempt, the application keeps the original round ID and allows the user to check the server.

If the server confirms that the document exists with the correct data, the attempt becomes cloud verified.

If the server confirms that the document does not exist, the user can retry the submission using the same round ID.

### 7. Firestore Security Rules

The Firestore rules restrict access to the authenticated owner of each attempt.

They also validate the submitted document fields.

The rules enforce:

- Authenticated owner access only.
- Exactly six required fields.
- Schema version 1.
- Variant A.
- Category ID 9.
- Exactly 10 questions.
- A score between 0 and 10.
- A valid server timestamp.
- No updates or deletions after creation.

This helps prevent unauthorized access and modification of submitted quiz results.

### 8. Error Handling

The application handles several failure situations, including:

- API request failures.
- Invalid or incomplete question data.
- Request timeouts.
- Firestore permission errors.
- Unavailable Firestore service.
- Resource-exhausted errors.
- Uncertain submission results.
- Attempt ID collisions.
- Authentication changes during asynchronous operations.

I also added development-only fault injection controls to test some of these situations without depending on an actual network failure.

## Application Workflow

1. The user signs in using Firebase Authentication.
2. The application requests 10 questions from OpenTDB.
3. The questions are validated and displayed.
4. The user answers all 10 questions.
5. The application calculates and freezes the final score.
6. The user submits the completed attempt.
7. Firestore checks whether the round ID already exists.
8. The application verifies the saved attempt using a server read.
9. The application displays the cloud verification result.
10. The user can replay the quiz after the attempt is resolved.

## Project Structure

The main implementation files include:

```text
lib/
  main.dart
  firebase_options.dart

  models/
    trivia_question.dart

  services/
    trivia_service.dart
    attempt_repository.dart

  screens/
    quiz_screen.dart
    security_test_screen.dart
    validation_test_screen.dart
    concurrency_test_screen.dart
    collision_test_screen.dart
    stale_auth_test_screen.dart

  g01_main.dart
  g02_main.dart
  g03_main.dart
```

The project also includes the standard Flutter platform folders and Firebase configuration files.

## Testing

I tested the application using an Android emulator.

The main tests covered question loading, validation, quiz interaction, Firestore submission, recovery, security rules, and error handling.

### Core Tests

| Test | Description | Result |
|------|-------------|--------|
| T01 | Quiz API request | Passed |
| T02 | Question validation | Passed |
| T03 | Malformed API response handling | Passed |
| T04 | Quiz interaction and scoring | Passed |
| T05 | Results and replay | Passed |
| T06 | Firestore submission | Passed |
| T07 | Server retrieval after restart | Passed |
| T08 | Offline submission and recovery | Passed |
| T09 | Lost acknowledgement recovery | Passed |
| T10 | Cross-user security restrictions | Passed |
| T11 | Firestore schema and immutability | Passed |
| T12 | Firestore error handling | Passed |

### Graduate Investigations

**G01 — Concurrent Submissions**

I tested concurrent submissions using the same round ID and score.

The test confirmed that the submissions could be reconciled with the same saved attempt without creating a duplicate document.

**Result:** Passed

**G02 — Same-Round ID Collision**

I submitted a different score using an existing round ID.

The application detected the collision, and the original score and server timestamp remained unchanged.

**Result:** Passed

**G03 — Stale Authentication Response**

I tested what happens when a response associated with User A arrives after the authenticated account changes to User B.

The application rejected the stale response rather than applying it to the new user's session.

**Result:** Passed

All 12 core tests and three graduate investigations were completed successfully.

More detailed results are available in `ICA16_A_Test_Log.md`.

## Running the Application

### Requirements

Before running the project, make sure you have:

- Flutter SDK installed.
- Android Studio or VS Code.
- An Android emulator or physical Android device.
- Access to the configured Firebase project.
- An enabled Firebase Authentication test account.

### Install Dependencies

Open the project directory and run:

```bash
flutter pub get
```

### Check the Project

```bash
dart format lib
flutter analyze
```

### Run the Main Application

```bash
flutter run
```

### Run Graduate Test Screens

G01:

```bash
flutter run -t lib/g01_main.dart
```

G02:

```bash
flutter run -t lib/g02_main.dart
```

G03:

```bash
flutter run -t lib/g03_main.dart
```

These additional entry points are used for graduate testing. The normal application starts from `lib/main.dart`.

## Building the APK

To build the Android release APK, run:

```bash
flutter build apk --release
```

The generated APK will be located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Submission Files

The final submission includes:

- Flutter project source code in GitHub.
- Android APK.
- ICA16 Class A Word report.
- Test log.
- Required testing evidence.

## Challenges and What I Learned

One of the main challenges was handling situations where Firestore did not immediately confirm whether a submission had been saved.

I learned that a successful local operation is not always enough to prove that a record exists on the server. This is why I added server-only verification and recovery using the original round ID.

Another important part was protecting submitted attempts. I used Firestore security rules to restrict access, validate document fields, and prevent users from modifying completed attempts.

The graduate tests also helped me understand why concurrent requests, document collisions, and authentication changes need to be handled carefully.

Overall, this assignment helped me gain more experience working with Flutter, REST APIs, Firebase Authentication, Firestore transactions, security rules, and asynchronous application states.


