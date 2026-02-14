import { LoginForm } from '@/components/auth/LoginForm'
import Link from 'next/link'

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center p-4 bg-gradient-to-br from-blue-50 to-indigo-100">
      <div className="w-full max-w-md space-y-4">
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">BudgetApp</h1>
          <p className="text-gray-600">Din smarta budgetverktyg</p>
        </div>
        <LoginForm />
        <p className="text-center text-sm text-gray-600">
          Inget konto än?{' '}
          <Link href="/signup" className="text-blue-600 hover:underline font-medium">
            Skapa konto
          </Link>
        </p>
      </div>
    </div>
  )
}