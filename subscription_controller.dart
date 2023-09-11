import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../utils/abs_toasts.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:http/http.dart' as http;

class SubscriptionController extends GetxController {
  late StreamSubscription<dynamic> subscription;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  List<ProductDetails>? products;
  List<PurchaseDetails> _purchases = [];

  String selectedProductID = 'com.testApp.weekly';
  bool isWeekly = true;
  bool isMonthly = false;
  bool isYearly = false;
  var isSubscribed = false.obs;

  void selectPlan(String type) {
    switch (type) {
      case 'Weekly':
        isWeekly = true;
        isMonthly = false;
        isYearly = false;
        selectedProductID = 'com.testApp.weekly';
        break;
      case 'Monthly':
        isWeekly = false;
        isMonthly = true;
        isYearly = false;
        selectedProductID = 'com.testApp.monthly';
        break;
      case 'Yearly':
        isWeekly = false;
        isMonthly = false;
        isYearly = true;
        selectedProductID = 'com.testApp.annual';
        break;
    }
    update();
  }

  void listenSubscription(BuildContext context) {
    final Stream purchaseUpdated = InAppPurchase.instance.purchaseStream;
    subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList, context);
    }, onDone: () {
      print('IN-APP-PURCHASE-ON-DONE');
      subscription.cancel();
    }, onError: (error) {
      Toasts.flushBarError(error.toString(), context);
      print('IN-APP-PURCHASE-LISTEN-ERROR $error');
    });
    fetchSubscription();
  }

  void _listenToPurchaseUpdated(
      List<PurchaseDetails> purchaseDetailsList, BuildContext context) {
    purchaseDetailsList.forEach((PurchaseDetails purchaseDetails) async {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        completePurchase(purchaseDetailsList, context);
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          PurchaseVerificationData(
            localVerificationData:
                purchaseDetails.verificationData.localVerificationData,
            serverVerificationData:
                purchaseDetails.verificationData.serverVerificationData,
            source: purchaseDetails.verificationData.source,
          );

          bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            // Unlock products and verify from server
            // DeliverProduct;
          } else {
            // Handle Invalid Purchase;
          }
          Toasts.flushBarSuccess(
              'Congratulation! \nYou have Subscribed Successfully.', context);
          subscriptionPurchased(context);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          if (purchaseDetailsList.isNotEmpty) {
            var purchaseList = purchaseDetailsList
                .where((element) => element.productID == selectedProductID)
                .toList();
            PurchaseDetails purchaseDetail = purchaseList[0];
            await InAppPurchase.instance.completePurchase(purchaseDetail);
          }
        }
      }
    });
  }

  Future<void> fetchSubscription() async {
    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      products = [];
      update();
      return;
    }
    Set<String> kIds = <String>{
      'com.testApp.weekly',
      'com.testApp.monthly',
      'com.testApp.annual'
    }.toSet();
    final ProductDetailsResponse response =
        await InAppPurchase.instance.queryProductDetails(kIds);
    if (response.notFoundIDs.isNotEmpty) {
      print('IN-APP-PURCHASE-NO-PRODUCTS-FOUND');
    }
    products = response.productDetails;
    update();
  }

  void completePurchase(
      List<PurchaseDetails> purchaseDetailsList, BuildContext context) {
    if (purchaseDetailsList.isNotEmpty) {
      var purchaseList = purchaseDetailsList
          .where((element) => element.productID == selectedProductID)
          .toList();
      PurchaseDetails purchaseDetails = purchaseList[0];
      _inAppPurchase.completePurchase(purchaseDetails);
      Toasts.flushBarSuccess(
          'Congratulation! \nYou have Subscribed Successfully.', context);
      subscriptionPurchased(context);
    }
  }

  Future<void> purchasePlan(BuildContext context) async {
    var selectedProduct =
        products!.firstWhere((element) => element.id == selectedProductID);
    final Map<String, PurchaseDetails> purchases =
        Map<String, PurchaseDetails>.fromEntries(
            _purchases.map((PurchaseDetails purchase) {
      if (purchase.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchase);
      }
      return MapEntry<String, PurchaseDetails>(purchase.productID, purchase);
    }));
    final GooglePlayPurchaseDetails? oldPurchaseDetails =
        _getOldSubscription(selectedProduct, purchases);
    final PurchaseParam purchaseParam = GooglePlayPurchaseParam(
        productDetails: selectedProduct,
        changeSubscriptionParam: oldPurchaseDetails == null
            ? null
            : ChangeSubscriptionParam(
                oldPurchaseDetails: oldPurchaseDetails,
                prorationMode: ProrationMode.immediateWithTimeProration),
        applicationUserName: "Test App");

    bool isPurchased = await InAppPurchase.instance
        .buyNonConsumable(purchaseParam: purchaseParam);
    if (isPurchased) {
      // VALID PURCHASE;
    } else {
      Toasts.flushBarError('Something went wrong', context);
    }
  }

  GooglePlayPurchaseDetails? _getOldSubscription(
      ProductDetails productDetails, Map<String, PurchaseDetails> purchases) {
    GooglePlayPurchaseDetails? oldSubscription;
    if (_purchases.isNotEmpty) {
      oldSubscription = _purchases[0].purchaseID as GooglePlayPurchaseDetails;
    }

    return oldSubscription;
  }

  Future<void> subscriptionPurchased(BuildContext context) async {
    await Future.delayed(const Duration(seconds: 2)).then((value) {
      Navigator.pop(context, true);
      SharedPref.setSubscribeStatus(true);
    });
  }

// handle cancelled events
  void checkCancelledPurchaseDetails() async {
    // first fetch plans
    fetchSubscription();
    final purchasedUpdated = InAppPurchase.instance.purchaseStream;
    StreamSubscription<List<PurchaseDetails>> _subscription =
        purchasedUpdated.listen(_onPurchasedUpdated);
    await InAppPurchase.instance.restorePurchases();
    Future.delayed(Duration(seconds: 3), () {
      _subscription.cancel();
    });
  }

  void _onPurchasedUpdated(List<PurchaseDetails> purchaseDetailsList) {
    _purchases = purchaseDetailsList;
    if (purchaseDetailsList.isEmpty) {
      SharedPref.setSubscribeStatus(false);
      // Navigate to subscription UI
      if (!Get.find<SettingController>().isRatingDialogOpen) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          Get.to(const SubscriptionPage(),
              transition: Transition.downToUp,
              duration: const Duration(milliseconds: 1000));
        });
      }
    }
    purchaseDetailsList.forEach((purchaseDetails) async {
      if (purchaseDetails.status == PurchaseStatus.restored) {
        SharedPref.setSubscribeStatus(true);
        selectedProductID = purchaseDetails.productID;

        if (purchaseDetails.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchaseDetails);
        }
      }
    });
  }
}
