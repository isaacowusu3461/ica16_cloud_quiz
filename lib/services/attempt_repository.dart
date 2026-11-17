
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AttemptStatus {
  cloudVerified,
  notFound,
  verificationUnavailable,
  permissionDenied,
  collision,
  saveUnknown,
}

enum SubmissionFault {
  none,
  unavailable,
  resourceExhausted,
}

class AttemptResult {
  final AttemptStatus status;
  final String message;
  final Map<String, dynamic>? data;

  const AttemptResult(this.status, this.message, [this.data]);
}

class AttemptRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  AttemptRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  // Generate the ID before submitting. A retry keeps this same ID.
  String createRoundId() {
    return firestore.collection('users').doc().id;
  }

  DocumentReference<Map<String, dynamic>> attemptRef(
    String uid,
    String roundId,
  ) {
    return firestore
        .collection('users')
        .doc(uid)
        .collection('attempts')
        .doc(roundId);
  }

  Map<String, dynamic> createPayload(int score) {
    return {
      'schemaVersion': 1,
      'variant': 'A',
      'categoryId': 9,
      'questionCount': 10,
      'correctCount': score,
      'submittedAt': FieldValue.serverTimestamp(),
    };
  }

  // Check the fixed fields and the resolved server timestamp.
  bool matchesPayload(Map<String, dynamic>? data, int score) {
    if (data == null || data.length != 6) return false;

    return data['schemaVersion'] == 1 &&
        data['variant'] == 'A' &&
        data['categoryId'] == 9 &&
        data['questionCount'] == 10 &&
        data['correctCount'] == score &&
        data['submittedAt'] is Timestamp;
  }

  // Only a server response can confirm a completed cloud save.
  Future<AttemptResult> verifyAttempt({
    required String uid,
    required String roundId,
    required int score,
  }) async {
    if (auth.currentUser?.uid != uid) {
      return const AttemptResult(
        AttemptStatus.permissionDenied,
        'The signed-in account has changed.',
      );
    }

    try {
      final snapshot = await attemptRef(uid, roundId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (auth.currentUser?.uid != uid) {
        return const AttemptResult(
          AttemptStatus.permissionDenied,
          'The account changed during verification.',
        );
      }

      if (!snapshot.exists) {
        return const AttemptResult(
          AttemptStatus.notFound,
          'The server confirmed that this round has no saved attempt. '
          'You can retry using the same round ID.',
        );
      }

      if (snapshot.metadata.hasPendingWrites) {
        return const AttemptResult(
          AttemptStatus.verificationUnavailable,
          'The attempt still has pending writes.',
        );
      }

      final data = snapshot.data();

      if (!matchesPayload(data, score)) {
        return const AttemptResult(
          AttemptStatus.collision,
          'The server record does not match this round.',
        );
      }

      return AttemptResult(
        AttemptStatus.cloudVerified,
        'Cloud verified. The server confirmed the saved attempt.',
        data,
      );
    } on TimeoutException {
      return const AttemptResult(
        AttemptStatus.verificationUnavailable,
        'Server verification timed out. Try again when online.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        return AttemptResult(
          AttemptStatus.permissionDenied,
          'Server access denied: ${error.code}.',
        );
      }

      return AttemptResult(
        AttemptStatus.verificationUnavailable,
        'Server verification unavailable: ${error.code}.',
      );
    } catch (_) {
      return const AttemptResult(
        AttemptStatus.verificationUnavailable,
        'Could not verify the attempt with the server.',
      );
    }
  }

  Future<AttemptResult> submitAttempt({
    required String uid,
    required String roundId,
    required int score,
    bool injectLostAcknowledgement = false,
    SubmissionFault fault = SubmissionFault.none,
  }) async {
    if (auth.currentUser?.uid != uid) {
      return const AttemptResult(
        AttemptStatus.permissionDenied,
        'Please sign in with the original account.',
      );
    }

    if (score < 0 || score > 10) {
      return const AttemptResult(
        AttemptStatus.collision,
        'The score must be between 0 and 10.',
      );
    }

    // T12 development faults happen before any Firestore write.
    // This lets us test the error states without consuming a round.
    if (fault == SubmissionFault.unavailable) {
      return const AttemptResult(
        AttemptStatus.saveUnknown,
        'Simulated unavailable: Firestore could not be reached. '
        'No write was started by this test. Recover from the server.',
      );
    }

    if (fault == SubmissionFault.resourceExhausted) {
      return const AttemptResult(
        AttemptStatus.saveUnknown,
        'Simulated resource-exhausted: Firestore reported a '
        'resource limit. No write was started by this test. '
        'Recover from the server.',
      );
    }

    final ref = attemptRef(uid, roundId);

    try {
      // Read first, then create only when the document is missing.
      await firestore.runTransaction((transaction) async {
        final existing = await transaction.get(ref);

        if (existing.exists) {
          if (!matchesPayload(existing.data(), score)) {
            throw StateError('Attempt collision');
          }
          return;
        }

        transaction.set(ref, createPayload(score));
      }).timeout(const Duration(seconds: 15));

      if (auth.currentUser?.uid != uid) {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'Authentication changed after submission. '
          'The save outcome needs reconciliation.',
        );
      }

      // T09: the real transaction succeeded, but we hide its response.
      if (injectLostAcknowledgement) {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'Test fault: acknowledgement suppressed after commit. '
          'Recover this attempt from the server.',
        );
      }

      return verifyAttempt(
        uid: uid,
        roundId: roundId,
        score: score,
      );
    } on StateError {
      return const AttemptResult(
        AttemptStatus.collision,
        'An attempt with this ID already exists with different values.',
      );
    } on TimeoutException {
      return const AttemptResult(
        AttemptStatus.saveUnknown,
        'Submission timed out. The outcome is unknown. '
        'Check the server before retrying.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated') {
        return AttemptResult(
          AttemptStatus.permissionDenied,
          'Submission denied: ${error.code}.',
        );
      }

      if (error.code == 'resource-exhausted') {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'Firestore resource limit reached. '
          'Recover the original round before retrying.',
        );
      }

      if (error.code == 'unavailable') {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'Firestore is unavailable. '
          'Recover the original round when online.',
        );
      }

      return AttemptResult(
        AttemptStatus.saveUnknown,
        'Submission outcome unknown: ${error.code}. '
        'Check the server before retrying.',
      );
    } catch (_) {
      return const AttemptResult(
        AttemptStatus.saveUnknown,
        'The submission outcome is unknown. '
        'Verify the server record before retrying.',
      );
    }
  }
}
