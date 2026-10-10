/// Whether a recurring series represents a currently active upcoming expense.
/// Unknown and user-disabled lifecycle states deliberately abstain.
bool isActiveRecurringExpense({
  required String status,
  required String kind,
}) =>
    status == 'active' && kind != 'income';
