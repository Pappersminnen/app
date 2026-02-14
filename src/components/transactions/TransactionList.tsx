'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Trash2 } from 'lucide-react'

interface Transaction {
  id: string
  description: string
  amount: number
  type: 'expense' | 'income'
  transaction_date: string
  category?: {
    name: string
    color: string
  }
}

interface TransactionListProps {
  transactions: Transaction[]
  organizationId: string
}

export function TransactionList({ transactions, organizationId }: TransactionListProps) {
  const [deleting, setDeleting] = useState<string | null>(null)
  const router = useRouter()
  const supabase = createClient()

  const handleDelete = async (id: string) => {
    if (!confirm('Är du säker på att du vill ta bort denna transaktion?')) {
      return
    }

    setDeleting(id)

    const { error } = await supabase
      .from('transactions')
      .delete()
      .eq('id', id)

    setDeleting(null)

    if (error) {
      console.error('Error deleting transaction:', error)
      return
    }

    router.refresh()
  }

  if (transactions.length === 0) {
    return (
      <div className="text-center py-12 bg-white rounded-lg shadow">
        <p className="text-gray-500">Inga transaktioner än</p>
        <p className="text-sm text-gray-400 mt-2">Klicka på "Ny Transaktion" för att komma igång</p>
      </div>
    )
  }

  return (
    <div className="bg-white rounded-lg shadow overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Datum</TableHead>
            <TableHead>Beskrivning</TableHead>
            <TableHead>Kategori</TableHead>
            <TableHead className="text-right">Belopp</TableHead>
            <TableHead className="w-[50px]"></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {transactions.map((transaction) => (
            <TableRow key={transaction.id}>
              <TableCell>
                {new Date(transaction.transaction_date).toLocaleDateString('sv-SE')}
              </TableCell>
              <TableCell className="font-medium">{transaction.description}</TableCell>
              <TableCell>
                {transaction.category && (
                  <span 
                    className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
                    style={{ 
                      backgroundColor: transaction.category.color + '20',
                      color: transaction.category.color 
                    }}
                  >
                    {transaction.category.name}
                  </span>
                )}
              </TableCell>
              <TableCell className={`text-right font-semibold ${
                transaction.type === 'expense' ? 'text-red-600' : 'text-green-600'
              }`}>
                {transaction.type === 'expense' ? '-' : '+'}{Number(transaction.amount).toLocaleString('sv-SE')} kr
              </TableCell>
              <TableCell>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleDelete(transaction.id)}
                  disabled={deleting === transaction.id}
                >
                  <Trash2 className="h-4 w-4 text-red-500" />
                </Button>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}