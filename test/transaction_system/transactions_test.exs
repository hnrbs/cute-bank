defmodule TransactionSystem.TransactionsTest do
  alias TransactionSystem.Transactions.Entry
  alias TransactionSystem.Transactions
  alias TransactionSystem.Transactions.Balance
  use TransactionSystem.DataCase

  import TransactionSystem.AccountsFixtures
  import TransactionSystem.TransactionsFixtures

  describe "transaction_entries" do
    test "create_entry/3 with valid data creates a entry and updates user balance" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 500])

      assert {:ok, {credit, debit}} = Transactions.create_entry(sender, receiver.cpf, 500)
      assert credit.user_id == sender.id
      assert credit.amount == 500
      assert credit.kind == :credit

      assert debit.user_id == receiver.id
      assert debit.amount == 500
      assert debit.kind == :debit

      %Balance{total: sender_balance} = sender |> Ecto.assoc(:balance) |> Repo.one!()
      %Balance{total: receiver_balance} = receiver |> Ecto.assoc(:balance) |> Repo.one!()

      assert sender_balance == 0
      assert receiver_balance == 500
    end

    test "create_entry/3 consistently updates the user balance and race conditions doesn't occur" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 10])


      # Don't spawn more than 10 tasks, since there are only 10 database connections available
      # TODO: I'm not quite sure if this test actually detects race conditions.
      #       Look for how to properly do it.
      tasks = Enum.map(1..10, fn _ ->
        Task.async(fn ->
          {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)
        end)
      end)

      Task.await_many(tasks, :infinity)

      %Balance{total: sender_balance} = sender |> Ecto.assoc(:balance) |> Repo.one!()
      assert sender_balance == 0

      %Balance{total: receiver_balance} = receiver |> Ecto.assoc(:balance) |> Repo.one!()
      assert receiver_balance == 10
    end

    test "create_entry/3 fails to create entries when sender doesn't have enough money" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      assert {:error, :not_enough_funds} = Transactions.create_entry(sender, receiver.cpf, 1)
    end
  end

  describe "balance_deposit_and_withdraw" do
    test "withdraw/2 updates user balance" do
      sender = user_fixture()
      _receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 11])

      {:ok, amount} = Transactions.withdraw(sender, 5)

      assert amount == 6
    end

    test "withdraw/2 fails if user doesnt have enough funds" do
      sender = user_fixture()
      _receiver = user_fixture(%{cpf: "222.222.222-22"})

      assert {:error, :not_enough_funds} = Transactions.withdraw(sender, 5)
    end

    test "deposit/2 updates user balance" do
      sender = user_fixture()
      _receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 10])

      {:ok, amount} = Transactions.deposit(sender, 5)

      assert amount == 15
    end
  end

  describe "refund_transaction" do
    test "refund/2 marks transactions as refunded and updates the users balances" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 10])

      {:ok, {%Entry{transaction_id: transaction_id} = _credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 5)
      assert :ok = Transactions.refund(sender, transaction_id)

      sender = sender |> refresh()
      assert sender.balance.total == 10

      receiver = receiver |> refresh()
      assert receiver.balance.total == 0
    end

    test "refund/2 can't be used by the receivers" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 10])

      {:ok, {%Entry{transaction_id: transaction_id} = _credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 5)
      {:error, :user_is_not_the_transaction_owner} = Transactions.refund(receiver, transaction_id)
    end

    test "refund/2 can't refund the same transaction twice" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})

      sender
      |> Ecto.assoc(:balance)
      |> Repo.update_all(set: [total: 10])

      {:ok, {%Entry{transaction_id: transaction_id} = _credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 5)
      :ok = Transactions.refund(sender, transaction_id)
      assert {:error, :transaction_not_found} = Transactions.refund(sender, transaction_id)
    end

    test "refund/2 can't be used when receiver hasn't enough funds" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})
      sender |> deposit(5)

      {:ok, {%Entry{transaction_id: transaction_id} = _credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 5)
      receiver |> withdraw(5)

      assert {:error, :not_enough_funds} = Transactions.refund(sender, transaction_id)
    end
  end

  describe "search transaction entries" do
    test "search_date_range/3 returns all transactions made by a user in a date range" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})
      sender |> deposit(3)

      start_date = DateTime.now!("Etc/UTC") |> DateTime.to_iso8601()
      {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)
      {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)
      {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)
      end_date = DateTime.now!("Etc/UTC") |> DateTime.to_iso8601()

      transactions = Transactions.search_date_range(start_date, end_date, sender)

      assert length(transactions) == 3
    end

    test "search_date_range/3 doesnt returns transactions from other users" do
      sender = user_fixture()
      receiver = user_fixture(%{cpf: "222.222.222-22"})
      other_sender = user_fixture(%{cpf: "333.333.333-33"})
      other_receiver = user_fixture(%{cpf: "555.555.555-55"})

      sender |> deposit(2)
      other_sender |> deposit(1)

      start_date = DateTime.now!("Etc/UTC") |> DateTime.to_iso8601()
      {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)
      {:ok, {_credit, _debit}} = Transactions.create_entry(sender, receiver.cpf, 1)

      {:ok, {_credit, _debit}} = Transactions.create_entry(other_sender, other_receiver.cpf, 1)
      end_date = DateTime.now!("Etc/UTC") |> DateTime.to_iso8601()

      transactions = Transactions.search_date_range(start_date, end_date, sender)

      assert length(transactions) == 2
    end
  end
end
