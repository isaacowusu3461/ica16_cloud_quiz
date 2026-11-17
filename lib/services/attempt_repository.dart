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

class AttemptResult {
  final AttemptStatus status;
  final String message;
  final Map<String, dynamic>? data;

  const AttemptResult(this.status, this.message, [this.data]);
}

class AttemptRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  AttemptRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : firestore = firestore ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;

  // This creates an ID without saving anything to Firestore.
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

  // A saved attempt must have exactly the six required fields.
  bool matchesPayload(Map<String, dynamic>? data, int score) {
    if (data == null || data.length != 6) {
      return false;
    }

    return data['schemaVersion'] == 1 &&
        data['variant'] == 'A' &&
        data['categoryId'] == 9 &&
        data['questionCount'] == 10 &&
        data['correctCount'] == score &&
        data['submittedAt'] is Timestamp;
  }

  // Check the actual server record instead of trusting cached data.
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
        'Server verification timed out. Check your connection '
        'and try again.',
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

    final ref = attemptRef(uid, roundId);

    try {
      // Firestore may rerun a transaction, so no UI changes happen here.
      await firestore
          .runTransaction((transaction) async {
            // Read before writing to avoid overwriting an existing attempt.
            final existing = await transaction.get(ref);

            if (existing.exists) {
              if (!matchesPayload(existing.data(), score)) {
                throw StateError('Attempt collision');
              }

              // The same round was already saved with matching values.
              return;
            }

            transaction.set(ref, createPayload(score));
          })
          .timeout(const Duration(seconds: 15));

      if (auth.currentUser?.uid != uid) {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'The account changed after submission. '
          'The save outcome needs reconciliation.',
        );
      }

      // Test-only fault: the real transaction already completed.
      if (injectLostAcknowledgement) {
        return const AttemptResult(
          AttemptStatus.saveUnknown,
          'Test fault: acknowledgement suppressed after commit. '
          'Recover this attempt from the server.',
        );
      }

      return verifyAttempt(uid: uid, roundId: roundId, score: score);
    } on StateError {
      return const AttemptResult(
        AttemptStatus.collision,
        'An attempt with this ID already exists with different values.',
      );
    } on TimeoutException {
      // A timeout does not prove that Firestore rejected the write.
      return const AttemptResult(
        AttemptStatus.saveUnknown,
        'Submission timed out. The save outcome is unknown. '
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

      // Network and availability failures may have an unknown outcome.
      return AttemptResult(
        AttemptStatus.saveUnknown,
        'Submission outcome unknown: ${error.code}. '
        'Recover from the server before retrying.',
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
